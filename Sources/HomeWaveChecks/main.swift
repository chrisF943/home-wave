import Foundation

var failures = 0

func check(_ condition: Bool, _ label: String) {
    if condition {
        print("PASS: \(label)")
    } else {
        failures += 1
        print("FAIL: \(label)")
    }
}

func checkLess(_ a: Float, _ b: Float, _ label: String) {
    check(a < b, "\(label) (\(a) < \(b))")
}

func checkGreater(_ a: Float, _ b: Float, _ label: String) {
    check(a > b, "\(label) (\(a) > \(b))")
}

runSpectrumAnalyzerChecks()

if failures > 0 {
    print("\(failures) check(s) FAILED")
    exit(1)
}
print("All checks passed")
