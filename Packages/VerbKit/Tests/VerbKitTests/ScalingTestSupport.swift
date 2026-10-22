import Foundation
import XCTest

/// Checks that work grows roughly linearly with input size, without depending on
/// how fast or busy the machine is. Wall-clock limits flake on loaded CI runners,
/// but a run at 10× the size taking about 10× as long holds on any machine.
///
/// `work` runs on inputs of `small` and 10 × `small`. Each run is timed by the
/// thread's CPU time, so time spent preempted by other processes doesn't count.
/// The two sizes are timed in alternation and the fastest of `runs` is kept for
/// each, which evens out what's left (cache and memory-bandwidth contention).
/// Linear (or n log n) work gives a ratio of about 10; an accidental O(n²) gives
/// about 100. The default limit of 30 sits between the two with room either side.
///
/// `prepare(size)` builds the input outside the timed part.
func XCTAssertScalesLinearly<Input>(
    small: Int = 500, runs: Int = 5, maxRatio: Double = 30,
    prepare: (Int) -> Input, _ work: (Input) -> Void,
    file: StaticString = #filePath, line: UInt = #line
) {
    let large = small * 10
    let smallInput = prepare(small), largeInput = prepare(large)
    work(smallInput); work(largeInput)    // warm up caches and lazy state
    var fastestSmall = TimeInterval.infinity, fastestLarge = TimeInterval.infinity
    for _ in 0..<runs {
        fastestSmall = min(fastestSmall, time { work(smallInput) })
        fastestLarge = min(fastestLarge, time { work(largeInput) })
    }
    let ratio = fastestLarge / max(fastestSmall, 1e-6)
    XCTAssertLessThan(
        ratio, maxRatio,
        "\(large) took \(ratio)× as long as \(small) (\(fastestLarge) s vs \(fastestSmall) s); expected about 10× for linear work",
        file: file, line: line
    )
}

/// CPU time the current thread spends in `work`. The code under test is single-threaded.
private func time(_ work: () -> Void) -> TimeInterval {
    let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    work()
    return TimeInterval(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1e9
}
