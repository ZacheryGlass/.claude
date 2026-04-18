// statusline: fast status-line renderer for Claude Code.
// Reads JSON on stdin, writes a single status line to stdout.
package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

const (
	cacheTTLSec      = 600         // git info cache lifetime
	timerWindowSec   = 3600        // 60-minute Anthropic cache window
	gcOlderThanHours = 48          // delete session files older than this
	clearMatchTail   = 5           // tail N lines of transcript on mtime change
)

// Input matches the subset of statusline JSON we actually read.
type Input struct {
	SessionID      string `json:"session_id"`
	TranscriptPath string `json:"transcript_path"`
	Model          struct {
		DisplayName string `json:"display_name"`
	} `json:"model"`
	ContextWindow struct {
		RemainingPercentage *float64 `json:"remaining_percentage"`
		CurrentUsage        *struct {
			CacheReadInputTokens     int64 `json:"cache_read_input_tokens"`
			CacheCreationInputTokens int64 `json:"cache_creation_input_tokens"`
		} `json:"current_usage"`
	} `json:"context_window"`
	Cost struct {
		TotalAPIDurationMS int64 `json:"total_api_duration_ms"`
	} `json:"cost"`
	Workspace struct {
		CurrentDir string `json:"current_dir"`
		ProjectDir string `json:"project_dir"`
	} `json:"workspace"`
}

func main() {
	// Empty stdin -> exit silent (matches PS).
	raw, err := io.ReadAll(os.Stdin)
	if err != nil || len(bytes.TrimSpace(raw)) == 0 {
		return
	}
	var in Input
	if err := json.Unmarshal(raw, &in); err != nil {
		return
	}

	// Resolve cache file (per session_id).
	home := os.Getenv("USERPROFILE")
	if home == "" {
		home = os.Getenv("HOME")
	}
	cacheDir := filepath.Join(home, ".claude", ".statusline_cache")
	_ = os.MkdirAll(cacheDir, 0o755)
	cacheFile := filepath.Join(cacheDir, in.SessionID)

	cache, _ := readCache(cacheFile)
	updated := false

	modelName := in.Model.DisplayName
	if modelName == "" {
		modelName = "Claude"
	}
	isHaiku := strings.Contains(strings.ToLower(modelName), "haiku")

	// --- Effort label (skip for Haiku) ---
	effortLabel := ""
	if !isHaiku {
		settingsPath := filepath.Join(home, ".claude", "settings.json")
		if st, err := os.Stat(settingsPath); err == nil {
			mtimeKey := strconv.FormatInt(st.ModTime().UnixMilli(), 10)
			if cache["SETTINGS_TIME_V2"] == mtimeKey {
				effortLabel = cache["EFFORT_LABEL"]
			} else {
				if newLabel, ok := readEffortLabel(settingsPath); ok {
					effortLabel = newLabel
					cache["SETTINGS_TIME_V2"] = mtimeKey
					cache["EFFORT_LABEL"] = effortLabel
					updated = true
				} else if v, ok := cache["EFFORT_LABEL"]; ok {
					effortLabel = v
				}
			}
		}
	}

	// --- Cache info segment ---
	cacheInfo := ""
	if u := in.ContextWindow.CurrentUsage; u != nil {
		read, write := u.CacheReadInputTokens, u.CacheCreationInputTokens
		if read > 0 || write > 0 {
			cacheInfo = "\u26A1 " + formatCount(read) + "/" + formatCount(write)
		}
	}

	// --- /clear and /compact detection (FIXED: matches <command-name>/x</command-name>) ---
	if in.TranscriptPath != "" {
		if st, err := os.Stat(in.TranscriptPath); err == nil {
			tmtime := strconv.FormatInt(st.ModTime().UnixMilli(), 10)
			if cache["TRANSCRIPT_MTIME"] != tmtime {
				cache["TRANSCRIPT_MTIME"] = tmtime
				updated = true
				if lines, err := tailLines(in.TranscriptPath, clearMatchTail); err == nil {
					if cleared := scanForClear(lines, cache["LAST_CLEAR_TIME"]); cleared > 0 {
						for k := range cache {
							if strings.HasPrefix(k, "TIMER_") {
								delete(cache, k)
							}
						}
						cache["LAST_CLEAR_TIME"] = strconv.FormatInt(cleared, 10)
						updated = true
					}
				}
			}
		}
	}

	// --- Per-model timer state machine ---
	apiDuration := in.Cost.TotalAPIDurationMS
	cachedAPI, hasBaseline := int64(0), false
	if v, ok := cache["TOTAL_API_DURATION"]; ok {
		hasBaseline = true
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			cachedAPI = n
		}
	}
	if apiDuration < cachedAPI {
		// Reset (cleared / switched session). Stamp only if there's also a fresh call.
		if apiDuration > 0 {
			cache["TIMER_"+modelName] = strconv.FormatInt(time.Now().UnixMilli(), 10)
		}
		cache["TOTAL_API_DURATION"] = strconv.FormatInt(apiDuration, 10)
		updated = true
	} else if apiDuration > cachedAPI {
		if hasBaseline {
			cache["TIMER_"+modelName] = strconv.FormatInt(time.Now().UnixMilli(), 10)
		}
		// First observation: record baseline only (no stamp). Matches PS resume-defer rule.
		cache["TOTAL_API_DURATION"] = strconv.FormatInt(apiDuration, 10)
		updated = true
	}

	// --- Timer display ---
	timerStr := "\u23F3 No Cache"
	if t, ok := cache["TIMER_"+modelName]; ok {
		if ticks, err := strconv.ParseInt(t, 10, 64); err == nil {
			lastAPI := time.UnixMilli(ticks).UTC()
			ageSec := time.Since(lastAPI).Seconds()
			expiresIn := float64(timerWindowSec) - ageSec
			if expiresIn > 0 {
				mins := int(expiresIn) / 60
				secs := int(expiresIn) % 60
				timerStr = fmt.Sprintf("\u23F3 %dm %ds", mins, secs)
			} else {
				timerStr = "\u23F3 Expired"
			}
		}
	}

	// --- Project name ---
	projectName := "no-project"
	if in.Workspace.ProjectDir != "" {
		projectName = filepath.Base(in.Workspace.ProjectDir)
	} else if in.Workspace.CurrentDir != "" {
		projectName = filepath.Base(in.Workspace.CurrentDir)
	}

	// --- Git info (cache TTL 300s, single git invocation on miss) ---
	gitBranch, gitStatus := "", ""
	if cur := in.Workspace.CurrentDir; cur != "" {
		if _, err := os.Stat(filepath.Join(cur, ".git")); err == nil {
			now := time.Now().Unix()
			cacheTime, _ := strconv.ParseInt(cache["GIT_TIME"], 10, 64)
			if cache["GIT_DIR"] == cur && (now-cacheTime) < cacheTTLSec {
				gitBranch = cache["GIT_BRANCH"]
				gitStatus = cache["GIT_STATUS"]
			} else {
				gitBranch, gitStatus = readGitStatus(cur)
				cache["GIT_DIR"] = cur
				cache["GIT_TIME"] = strconv.FormatInt(now, 10)
				cache["GIT_BRANCH"] = gitBranch
				cache["GIT_STATUS"] = gitStatus
				updated = true
			}
		}
	}

	// --- Persist cache only if changed ---
	if updated {
		_ = writeCache(cacheFile, cache)
		// 1-in-20 GC throttle.
		if rand.Intn(20) == 0 {
			gcCacheDir(cacheDir)
		}
	}

	// --- Output ---
	var parts []string
	parts = append(parts, "\U0001F4C1 "+projectName)
	parts = append(parts, "\U0001F916 "+modelName+effortLabel)
	if cacheInfo != "" {
		parts = append(parts, cacheInfo)
	}
	if timerStr != "" {
		parts = append(parts, timerStr)
	}
	if gitBranch != "" {
		parts = append(parts, "\U0001F33F "+gitBranch+gitStatus)
	}
	if rp := in.ContextWindow.RemainingPercentage; rp != nil {
		pct := int(*rp + 0.5)
		if pct < 0 {
			pct = 0
		}
		color := "31"
		if pct > 50 {
			color = "32"
		} else if pct > 20 {
			color = "33"
		}
		parts = append(parts, fmt.Sprintf("\x1b[%sm%d%% Remaining\x1b[0m", color, pct))
	}

	// Force UTF-8 stdout (Windows default may be code-page).
	w := bufio.NewWriter(os.Stdout)
	w.WriteString(strings.Join(parts, " | "))
	w.WriteString("\n")
	w.Flush()
}

func formatCount(n int64) string {
	if n >= 1000 {
		// Match PS: [math]::Round($n / 1000, 1) -> banker's rounding to 1 decimal.
		v := float64(n) / 1000.0
		// Use 1-decimal formatting; trim trailing .0 if integer.
		s := strconv.FormatFloat(v, 'f', 1, 64)
		return s + "k"
	}
	return strconv.FormatInt(n, 10)
}

// --- Cache file I/O (KEY=VALUE\n, UTF-8). ---

var utf8BOM = []byte{0xEF, 0xBB, 0xBF}

func stripBOM(b []byte) []byte {
	if bytes.HasPrefix(b, utf8BOM) {
		return b[len(utf8BOM):]
	}
	return b
}

func readCache(path string) (map[string]string, error) {
	out := map[string]string{}
	data, err := os.ReadFile(path)
	if err != nil {
		return out, err
	}
	data = stripBOM(data)
	sc := bufio.NewScanner(bytes.NewReader(data))
	sc.Buffer(make([]byte, 0, 4096), 1<<20)
	for sc.Scan() {
		line := sc.Text()
		if i := strings.IndexByte(line, '='); i > 0 {
			out[line[:i]] = line[i+1:]
		}
	}
	return out, nil
}

func writeCache(path string, m map[string]string) error {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b bytes.Buffer
	for i, k := range keys {
		if i > 0 {
			b.WriteByte('\n')
		}
		b.WriteString(k)
		b.WriteByte('=')
		b.WriteString(m[k])
	}
	tmp := path + "." + strconv.Itoa(os.Getpid())
	if err := os.WriteFile(tmp, b.Bytes(), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func gcCacheDir(dir string) {
	cutoff := time.Now().Add(-time.Duration(gcOlderThanHours) * time.Hour)
	tempSuffix := regexp.MustCompile(`\.\d+$`)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		full := filepath.Join(dir, e.Name())
		info, err := e.Info()
		if err != nil {
			continue
		}
		if info.ModTime().Before(cutoff) || tempSuffix.MatchString(e.Name()) {
			_ = os.Remove(full)
		}
	}
}

// --- settings.json effort-level reading. ---

func readEffortLabel(path string) (string, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", false
	}
	data = stripBOM(data)
	var s struct {
		EffortLevel string `json:"effortLevel"`
	}
	if err := json.Unmarshal(data, &s); err != nil {
		return "", false
	}
	if s.EffortLevel == "" {
		return "", true
	}
	return " (" + titleCase(s.EffortLevel) + ")", true
}

func titleCase(s string) string {
	if s == "" {
		return ""
	}
	r, size := utf8.DecodeRuneInString(s)
	rest := s[size:]
	return string(unicode.ToUpper(r)) + strings.ToLower(rest)
}

// --- Transcript /clear and /compact scan. ---

var clearLineRE = regexp.MustCompile(`<command-name>/(?:clear|compact)</command-name>`)
var timestampRE = regexp.MustCompile(`"timestamp":"([^"]+)"`)
var legacyTimestampRE = regexp.MustCompile(`"timestamp":(\d+)`)

// scanForClear returns the newest clear-event timestamp (epoch ms) found in lines
// that is strictly greater than lastClear (string of int64 epoch ms). 0 if none.
func scanForClear(lines []string, lastClear string) int64 {
	last, _ := strconv.ParseInt(lastClear, 10, 64)
	var newest int64 = 0
	for _, line := range lines {
		if !clearLineRE.MatchString(line) {
			continue
		}
		var ts int64
		if m := timestampRE.FindStringSubmatch(line); len(m) == 2 {
			if t, err := time.Parse(time.RFC3339Nano, m[1]); err == nil {
				ts = t.UnixMilli()
			}
		}
		if ts == 0 {
			if m := legacyTimestampRE.FindStringSubmatch(line); len(m) == 2 {
				if n, err := strconv.ParseInt(m[1], 10, 64); err == nil {
					ts = n
				}
			}
		}
		if ts > last && ts > newest {
			newest = ts
		}
	}
	return newest
}

// tailLines returns the last n lines of a file. Reads the whole file (fine for
// jsonl transcripts up to a few MB; matches PS Get-Content -Tail).
func tailLines(path string, n int) ([]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	data = stripBOM(data)
	sc := bufio.NewScanner(bytes.NewReader(data))
	sc.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	ring := make([]string, 0, n)
	for sc.Scan() {
		if len(ring) < n {
			ring = append(ring, sc.Text())
		} else {
			copy(ring, ring[1:])
			ring[n-1] = sc.Text()
		}
	}
	return ring, sc.Err()
}

// --- Git status (one invocation, returns branch + dirty/ahead/behind suffix). ---

func readGitStatus(dir string) (branch, status string) {
	cmd := exec.Command("git", "-C", dir, "status", "--branch", "--porcelain=v1")
	out, err := cmd.Output()
	if err != nil {
		return "", ""
	}
	lines := strings.Split(strings.TrimRight(string(out), "\n"), "\n")
	if len(lines) == 0 {
		return "", ""
	}
	header := lines[0]
	switch {
	case strings.HasPrefix(header, "## HEAD"):
		short, err := exec.Command("git", "-C", dir, "rev-parse", "--short", "HEAD").Output()
		if err == nil {
			branch = "HEAD@" + strings.TrimSpace(string(short))
		}
	default:
		// "## branchname...remote [ahead 1, behind 2]"
		rest := strings.TrimPrefix(header, "## ")
		if i := strings.IndexAny(rest, ". "); i >= 0 {
			branch = rest[:i]
		} else {
			branch = rest
		}
	}
	if len(lines) > 1 {
		status = "*"
	}
	if m := regexp.MustCompile(`\[ahead (\d+)`).FindStringSubmatch(header); len(m) == 2 {
		status += "\u2191" + m[1]
	}
	if m := regexp.MustCompile(`behind (\d+)`).FindStringSubmatch(header); len(m) == 2 {
		status += "\u2193" + m[1]
	}
	return branch, status
}
