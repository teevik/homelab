package main

import (
	"bufio"
	"flag"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const (
	// Native AniMe Matrix resolution - 64x36 for 1:1 LED pixel mapping
	imgWidth  = 64
	imgHeight = 36
)

// SystemStats holds CPU, memory and disk usage percentages.
type SystemStats struct {
	CPUPercent  float64
	MemPercent  float64
	DiskPercent float64
}

// cpuTimes holds the relevant fields from /proc/stat.
type cpuTimes struct {
	idle  uint64
	total uint64
}

func main() {
	interval := flag.Duration("interval", 15*time.Second, "refresh interval")
	asusctlPath := flag.String("asusctl", "asusctl", "path to asusctl binary")
	outputPath := flag.String("output", "/tmp/anime-matrix-stats.png", "path to output image")
	flag.Parse()

	// Handle graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		log.Println("Shutting down, disabling AniMe Matrix display...")
		_ = exec.Command(*asusctlPath, "anime", "--enable-display", "false").Run()
		os.Exit(0)
	}()

	// Enable the display on startup
	if err := exec.Command(*asusctlPath, "anime", "--enable-display", "true").Run(); err != nil {
		log.Printf("Warning: failed to enable anime display: %v", err)
	}

	log.Printf("Starting anime-matrix-stats (interval=%s)", *interval)

	for {
		stats, err := getSystemStats()
		if err != nil {
			log.Printf("Error getting system stats: %v", err)
			time.Sleep(*interval)
			continue
		}

		log.Printf("CPU: %.1f%%  MEM: %.1f%%  DISK: %.1f%%", stats.CPUPercent, stats.MemPercent, stats.DiskPercent)

		if err := renderAndPush(stats, *outputPath, *asusctlPath); err != nil {
			log.Printf("Error rendering/pushing: %v", err)
		}

		time.Sleep(*interval)
	}
}

// getSystemStats collects CPU, memory and disk usage.
func getSystemStats() (*SystemStats, error) {
	cpu, err := getCPUPercent()
	if err != nil {
		return nil, fmt.Errorf("cpu: %w", err)
	}

	mem, err := getMemPercent()
	if err != nil {
		return nil, fmt.Errorf("mem: %w", err)
	}

	disk, err := getDiskPercent("/")
	if err != nil {
		return nil, fmt.Errorf("disk: %w", err)
	}

	return &SystemStats{
		CPUPercent:  cpu,
		MemPercent:  mem,
		DiskPercent: disk,
	}, nil
}

// readCPUTimes parses the first "cpu" line from /proc/stat.
func readCPUTimes() (cpuTimes, error) {
	f, err := os.Open("/proc/stat")
	if err != nil {
		return cpuTimes{}, err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "cpu ") {
			fields := strings.Fields(line)
			if len(fields) < 5 {
				return cpuTimes{}, fmt.Errorf("unexpected /proc/stat format")
			}

			var total, idle uint64
			for i, field := range fields[1:] {
				val, err := strconv.ParseUint(field, 10, 64)
				if err != nil {
					return cpuTimes{}, fmt.Errorf("parse field %d: %w", i, err)
				}
				total += val
				// Field index 3 (4th value after "cpu") is idle time
				if i == 3 {
					idle = val
				}
			}

			return cpuTimes{idle: idle, total: total}, nil
		}
	}

	return cpuTimes{}, fmt.Errorf("/proc/stat: no cpu line found")
}

// getCPUPercent measures CPU usage over a short sampling interval.
func getCPUPercent() (float64, error) {
	t1, err := readCPUTimes()
	if err != nil {
		return 0, err
	}

	time.Sleep(500 * time.Millisecond)

	t2, err := readCPUTimes()
	if err != nil {
		return 0, err
	}

	totalDelta := float64(t2.total - t1.total)
	idleDelta := float64(t2.idle - t1.idle)

	if totalDelta == 0 {
		return 0, nil
	}

	return (1.0 - idleDelta/totalDelta) * 100.0, nil
}

// getMemPercent reads /proc/meminfo to calculate memory usage percentage.
func getMemPercent() (float64, error) {
	f, err := os.Open("/proc/meminfo")
	if err != nil {
		return 0, err
	}
	defer f.Close()

	var memTotal, memAvailable uint64
	found := 0

	scanner := bufio.NewScanner(f)
	for scanner.Scan() && found < 2 {
		line := scanner.Text()

		if strings.HasPrefix(line, "MemTotal:") {
			memTotal, err = parseMemInfoValue(line)
			if err != nil {
				return 0, err
			}
			found++
		} else if strings.HasPrefix(line, "MemAvailable:") {
			memAvailable, err = parseMemInfoValue(line)
			if err != nil {
				return 0, err
			}
			found++
		}
	}

	if memTotal == 0 {
		return 0, fmt.Errorf("could not read MemTotal from /proc/meminfo")
	}

	used := memTotal - memAvailable
	return float64(used) / float64(memTotal) * 100.0, nil
}

// parseMemInfoValue extracts the numeric kB value from a /proc/meminfo line.
func parseMemInfoValue(line string) (uint64, error) {
	fields := strings.Fields(line)
	if len(fields) < 2 {
		return 0, fmt.Errorf("unexpected meminfo line: %s", line)
	}
	return strconv.ParseUint(fields[1], 10, 64)
}

// getDiskPercent returns disk usage percentage for the given mount point.
func getDiskPercent(path string) (float64, error) {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return 0, fmt.Errorf("statfs %s: %w", path, err)
	}

	total := stat.Blocks * uint64(stat.Bsize)
	free := stat.Bfree * uint64(stat.Bsize)

	if total == 0 {
		return 0, nil
	}

	used := total - free
	return float64(used) / float64(total) * 100.0, nil
}

// renderAndPush draws the three metric bars and pushes to the display.
func renderAndPush(stats *SystemStats, outputPath, asusctlPath string) error {
	img := image.NewGray(image.Rect(0, 0, imgWidth, imgHeight))

	// Fill black background
	for y := 0; y < imgHeight; y++ {
		for x := 0; x < imgWidth; x++ {
			img.SetGray(x, y, color.Gray{Y: 0})
		}
	}

	white := color.Gray{Y: 255}
	dim := color.Gray{Y: 60}

	// Layout: three rows of [Letter] [Bar] in the visible right portion
	// The AniMe Matrix diagonal layout means the right side is most visible
	startX := 17            // left edge of our drawing area (lower = more left in flipped view)
	barStartX := startX + 6 // after the letter + 1px gap
	fullBarWidth := imgWidth - barStartX - 3
	barHeight := 5

	// Each row has a different bar width to fit the diagonal display edge
	metrics := []struct {
		letter   [5][3]bool // 3x5 bitmap
		percent  float64
		barWidth int
	}{
		{letter: letterC, percent: stats.CPUPercent, barWidth: fullBarWidth},
		{letter: letterM, percent: stats.MemPercent, barWidth: fullBarWidth * 3 / 4},
		{letter: letterD, percent: stats.DiskPercent, barWidth: fullBarWidth / 2},
	}

	for i, m := range metrics {
		rowY := 1 + i*8 // vertical spacing between rows (lower = more up in flipped view)

		// Draw letter
		drawLetter(img, startX, rowY, m.letter, white)

		// Draw bar background (dim outline)
		barY := rowY
		for x := barStartX; x < barStartX+m.barWidth; x++ {
			img.SetGray(x, barY, dim)
			img.SetGray(x, barY+barHeight-1, dim)
		}
		for y := barY; y < barY+barHeight; y++ {
			img.SetGray(barStartX, y, dim)
			img.SetGray(barStartX+m.barWidth-1, y, dim)
		}

		// Draw filled portion
		pct := m.percent
		if pct > 100 {
			pct = 100
		}
		if pct < 0 {
			pct = 0
		}
		fillWidth := int(float64(m.barWidth-2) * pct / 100.0)
		for y := barY + 1; y < barY+barHeight-1; y++ {
			for x := barStartX + 1; x < barStartX+1+fillWidth; x++ {
				img.SetGray(x, y, white)
			}
		}
	}

	// Flip the image both vertically and horizontally (the AniMe Matrix display is rotated 180°)
	flipped := image.NewGray(img.Bounds())
	for y := 0; y < imgHeight; y++ {
		for x := 0; x < imgWidth; x++ {
			flipped.SetGray(x, y, img.GrayAt(imgWidth-1-x, imgHeight-1-y))
		}
	}

	// Write PNG
	f, err := os.Create(outputPath)
	if err != nil {
		return fmt.Errorf("create output file: %w", err)
	}
	defer f.Close()

	if err := png.Encode(f, flipped); err != nil {
		return fmt.Errorf("encode png: %w", err)
	}

	// Push to AniMe Matrix display using pixel-image mode for 1:1 LED mapping
	cmd := exec.Command(asusctlPath, "anime", "pixel-image", "--path", outputPath)
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("asusctl anime pixel-image: %v: %s", err, output)
	}

	return nil
}

// drawLetter renders a 3x5 bitmap letter onto the image.
func drawLetter(img *image.Gray, x, y int, bitmap [5][3]bool, c color.Gray) {
	for row := 0; row < 5; row++ {
		for col := 0; col < 3; col++ {
			if bitmap[row][col] {
				px := x + col
				py := y + row
				if px >= 0 && px < imgWidth && py >= 0 && py < imgHeight {
					img.SetGray(px, py, c)
				}
			}
		}
	}
}

// 3x5 bitmap font definitions for C, M, D
var letterC = [5][3]bool{
	{true, true, true},
	{true, false, false},
	{true, false, false},
	{true, false, false},
	{true, true, true},
}

var letterM = [5][3]bool{
	{true, false, true},
	{true, true, true},
	{true, true, true},
	{true, false, true},
	{true, false, true},
}

var letterD = [5][3]bool{
	{true, true, false},
	{true, false, true},
	{true, false, true},
	{true, false, true},
	{true, true, false},
}
