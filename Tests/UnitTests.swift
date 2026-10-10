#if EYE_REST_UNIT_TESTING
import Foundation

@main
struct UnitTests {
    @MainActor
    static func main() {
        var checks = 0
        var failures = 0
        runGammaTests { passed, label in
            checks += 1
            if !passed { failures += 1 }
            print("\(passed ? "PASS" : "FAIL") \(label)")
        }
        print("RESULT: \(checks - failures)/\(checks) passed (Mock only)")
        exit(failures == 0 ? 0 : 1)
    }
}
#endif
