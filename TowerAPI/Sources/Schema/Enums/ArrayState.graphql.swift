// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) import ApolloAPI

nonisolated public enum ArrayState: String, EnumType {
  case started = "STARTED"
  case stopped = "STOPPED"
  case newArray = "NEW_ARRAY"
  case reconDisk = "RECON_DISK"
  case disableDisk = "DISABLE_DISK"
  case swapDsbl = "SWAP_DSBL"
  case invalidExpansion = "INVALID_EXPANSION"
  case parityNotBiggest = "PARITY_NOT_BIGGEST"
  case tooManyMissingDisks = "TOO_MANY_MISSING_DISKS"
  case newDiskTooSmall = "NEW_DISK_TOO_SMALL"
  case noDataDisks = "NO_DATA_DISKS"
}
