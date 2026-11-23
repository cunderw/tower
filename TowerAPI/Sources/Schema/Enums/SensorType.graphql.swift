// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) import ApolloAPI

/// Type of temperature sensor
nonisolated public enum SensorType: String, EnumType {
  case cpuPackage = "CPU_PACKAGE"
  case cpuCore = "CPU_CORE"
  case motherboard = "MOTHERBOARD"
  case chipset = "CHIPSET"
  case gpu = "GPU"
  case disk = "DISK"
  case nvme = "NVME"
  case ambient = "AMBIENT"
  case vrm = "VRM"
  case custom = "CUSTOM"
}
