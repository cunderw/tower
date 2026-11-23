/// Memory in use, in bytes: total minus available, never below zero.
///
/// The server's `used` is total minus free, so it counts buffers and page
/// cache that the kernel gives back on demand. On a busy server that reads as
/// nearly full. `percentTotal` is (total − available) / total, so this figure
/// agrees with the percentage the gauge shows.
func memoryInUseBytes(total: Int64, available: Int64) -> Int64 {
  max(0, total - available)
}
