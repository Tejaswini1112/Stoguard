package packages

import (
	"testing"
	"time"
)

func TestScanFindsBrew(t *testing.T) {
	start := time.Now()
	out := Scan()
	t.Logf("count=%d elapsed=%s", len(out), time.Since(start))
	if len(out) == 0 {
		t.Fatal("expected installed packages, got 0")
	}
}
