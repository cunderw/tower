// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct DashboardQuery: GraphQLQuery {
  public static let operationName: String = "Dashboard"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query Dashboard { array { __typename state capacity { __typename kilobytes { __typename free used total } } parityCheckStatus { __typename status correcting progress errors speed date duration } disks { __typename id idx name device status temp size fsFree fsUsed fsSize fsType rotational numReads numWrites numErrors type } parities { __typename id idx name device status temp size fsFree fsUsed fsSize fsType rotational numReads numWrites numErrors type } caches { __typename id idx name device status temp size fsFree fsUsed fsSize fsType rotational numReads numWrites numErrors type } } info { __typename os { __typename distro release uptime } cpu { __typename brand cores threads } } metrics { __typename cpu { __typename percentTotal } memory { __typename percentTotal used total } } docker { __typename containers { __typename id state } } vms { __typename domains { __typename id state } } shares { __typename id } }"#
    ))

  public init() {}

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("array", Array.self),
      .field("info", Info.self),
      .field("metrics", Metrics.self),
      .field("docker", Docker.self),
      .field("vms", Vms.self),
      .field("shares", [Share].self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      DashboardQuery.Data.self
    ] }

    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **ARRAY**
    public var array: Array { __data["array"] }
    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **INFO**
    public var info: Info { __data["info"] }
    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **INFO**
    public var metrics: Metrics { __data["metrics"] }
    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **DOCKER**
    public var docker: Docker { __data["docker"] }
    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **VMS**
    ///
    /// #### Description:
    ///
    /// Get information about all VMs on the system
    public var vms: Vms { __data["vms"] }
    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **SHARE**
    public var shares: [Share] { __data["shares"] }

    /// Array
    ///
    /// Parent Type: `UnraidArray`
    nonisolated public struct Array: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.UnraidArray }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("state", GraphQLEnum<TowerAPI.ArrayState>.self),
        .field("capacity", Capacity.self),
        .field("parityCheckStatus", ParityCheckStatus.self),
        .field("disks", [Disk].self),
        .field("parities", [Parity].self),
        .field("caches", [Cach].self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        DashboardQuery.Data.Array.self
      ] }

      /// Current array state
      public var state: GraphQLEnum<TowerAPI.ArrayState> { __data["state"] }
      /// Current array capacity
      public var capacity: Capacity { __data["capacity"] }
      /// Current parity check status
      public var parityCheckStatus: ParityCheckStatus { __data["parityCheckStatus"] }
      /// Data disks in the current array
      public var disks: [Disk] { __data["disks"] }
      /// Parity disks in the current array
      public var parities: [Parity] { __data["parities"] }
      /// Caches in the current array
      public var caches: [Cach] { __data["caches"] }

      /// Array.Capacity
      ///
      /// Parent Type: `ArrayCapacity`
      nonisolated public struct Capacity: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.ArrayCapacity }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("kilobytes", Kilobytes.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DashboardQuery.Data.Array.Capacity.self
        ] }

        /// Capacity in kilobytes
        public var kilobytes: Kilobytes { __data["kilobytes"] }

        /// Array.Capacity.Kilobytes
        ///
        /// Parent Type: `Capacity`
        nonisolated public struct Kilobytes: TowerAPI.SelectionSet {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Capacity }
          @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("free", String.self),
            .field("used", String.self),
            .field("total", String.self),
          ] }
          @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            DashboardQuery.Data.Array.Capacity.Kilobytes.self
          ] }

          /// Free capacity
          public var free: String { __data["free"] }
          /// Used capacity
          public var used: String { __data["used"] }
          /// Total capacity
          public var total: String { __data["total"] }
        }
      }

      /// Array.ParityCheckStatus
      ///
      /// Parent Type: `ParityCheck`
      nonisolated public struct ParityCheckStatus: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.ParityCheck }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("status", GraphQLEnum<TowerAPI.ParityCheckStatus>.self),
          .field("correcting", Bool?.self),
          .field("progress", Int?.self),
          .field("errors", Int?.self),
          .field("speed", String?.self),
          .field("date", TowerAPI.DateTime?.self),
          .field("duration", Int?.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DashboardQuery.Data.Array.ParityCheckStatus.self
        ] }

        /// Status of the parity check
        public var status: GraphQLEnum<TowerAPI.ParityCheckStatus> { __data["status"] }
        /// Whether corrections are being written to parity
        public var correcting: Bool? { __data["correcting"] }
        /// Progress percentage of the parity check
        public var progress: Int? { __data["progress"] }
        /// Number of errors during the parity check
        public var errors: Int? { __data["errors"] }
        /// Speed of the parity check, in MB/s
        public var speed: String? { __data["speed"] }
        /// Date of the parity check
        public var date: TowerAPI.DateTime? { __data["date"] }
        /// Duration of the parity check in seconds
        public var duration: Int? { __data["duration"] }
      }

      /// Array.Disk
      ///
      /// Parent Type: `ArrayDisk`
      nonisolated public struct Disk: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.ArrayDisk }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", TowerAPI.PrefixedID.self),
          .field("idx", Int.self),
          .field("name", String?.self),
          .field("device", String?.self),
          .field("status", GraphQLEnum<TowerAPI.ArrayDiskStatus>?.self),
          .field("temp", Int?.self),
          .field("size", TowerAPI.BigInt?.self),
          .field("fsFree", TowerAPI.BigInt?.self),
          .field("fsUsed", TowerAPI.BigInt?.self),
          .field("fsSize", TowerAPI.BigInt?.self),
          .field("fsType", String?.self),
          .field("rotational", Bool?.self),
          .field("numReads", TowerAPI.BigInt?.self),
          .field("numWrites", TowerAPI.BigInt?.self),
          .field("numErrors", TowerAPI.BigInt?.self),
          .field("type", GraphQLEnum<TowerAPI.ArrayDiskType>.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DashboardQuery.Data.Array.Disk.self
        ] }

        public var id: TowerAPI.PrefixedID { __data["id"] }
        /// Array slot number. Parity1 is always 0 and Parity2 is always 29. Array slots
        /// will be 1 - 28. Cache slots are 30 - 53. Flash is 54.
        public var idx: Int { __data["idx"] }
        public var name: String? { __data["name"] }
        public var device: String? { __data["device"] }
        public var status: GraphQLEnum<TowerAPI.ArrayDiskStatus>? { __data["status"] }
        /// Disk temp - will be NaN if array is not started or DISK_NP
        public var temp: Int? { __data["temp"] }
        /// (KB) Disk Size total
        public var size: TowerAPI.BigInt? { __data["size"] }
        /// (KB) Free Size on the FS (Not present on Parity type drive)
        public var fsFree: TowerAPI.BigInt? { __data["fsFree"] }
        /// (KB) Used Size on the FS (Not present on Parity type drive)
        public var fsUsed: TowerAPI.BigInt? { __data["fsUsed"] }
        /// (KB) Total Size of the FS (Not present on Parity type drive)
        public var fsSize: TowerAPI.BigInt? { __data["fsSize"] }
        /// File system type for the disk
        public var fsType: String? { __data["fsType"] }
        /// Is the disk a HDD or SSD.
        public var rotational: Bool? { __data["rotational"] }
        /// Count of I/O read requests sent to the device I/O drivers. These statistics may be cleared at any time.
        public var numReads: TowerAPI.BigInt? { __data["numReads"] }
        /// Count of I/O writes requests sent to the device I/O drivers. These statistics may be cleared at any time.
        public var numWrites: TowerAPI.BigInt? { __data["numWrites"] }
        /// Number of unrecoverable errors reported by the device I/O drivers. Missing
        /// data due to unrecoverable array read errors is filled in on-the-fly using
        /// parity reconstruct (and we attempt to write this data back to the sector(s)
        /// which failed). Any unrecoverable write error results in disabling the disk.
        public var numErrors: TowerAPI.BigInt? { __data["numErrors"] }
        /// Type of Disk - used to differentiate Boot / Cache / Flash / Data (DATA) / Parity
        public var type: GraphQLEnum<TowerAPI.ArrayDiskType> { __data["type"] }
      }

      /// Array.Parity
      ///
      /// Parent Type: `ArrayDisk`
      nonisolated public struct Parity: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.ArrayDisk }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", TowerAPI.PrefixedID.self),
          .field("idx", Int.self),
          .field("name", String?.self),
          .field("device", String?.self),
          .field("status", GraphQLEnum<TowerAPI.ArrayDiskStatus>?.self),
          .field("temp", Int?.self),
          .field("size", TowerAPI.BigInt?.self),
          .field("fsFree", TowerAPI.BigInt?.self),
          .field("fsUsed", TowerAPI.BigInt?.self),
          .field("fsSize", TowerAPI.BigInt?.self),
          .field("fsType", String?.self),
          .field("rotational", Bool?.self),
          .field("numReads", TowerAPI.BigInt?.self),
          .field("numWrites", TowerAPI.BigInt?.self),
          .field("numErrors", TowerAPI.BigInt?.self),
          .field("type", GraphQLEnum<TowerAPI.ArrayDiskType>.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DashboardQuery.Data.Array.Parity.self
        ] }

        public var id: TowerAPI.PrefixedID { __data["id"] }
        /// Array slot number. Parity1 is always 0 and Parity2 is always 29. Array slots
        /// will be 1 - 28. Cache slots are 30 - 53. Flash is 54.
        public var idx: Int { __data["idx"] }
        public var name: String? { __data["name"] }
        public var device: String? { __data["device"] }
        public var status: GraphQLEnum<TowerAPI.ArrayDiskStatus>? { __data["status"] }
        /// Disk temp - will be NaN if array is not started or DISK_NP
        public var temp: Int? { __data["temp"] }
        /// (KB) Disk Size total
        public var size: TowerAPI.BigInt? { __data["size"] }
        /// (KB) Free Size on the FS (Not present on Parity type drive)
        public var fsFree: TowerAPI.BigInt? { __data["fsFree"] }
        /// (KB) Used Size on the FS (Not present on Parity type drive)
        public var fsUsed: TowerAPI.BigInt? { __data["fsUsed"] }
        /// (KB) Total Size of the FS (Not present on Parity type drive)
        public var fsSize: TowerAPI.BigInt? { __data["fsSize"] }
        /// File system type for the disk
        public var fsType: String? { __data["fsType"] }
        /// Is the disk a HDD or SSD.
        public var rotational: Bool? { __data["rotational"] }
        /// Count of I/O read requests sent to the device I/O drivers. These statistics may be cleared at any time.
        public var numReads: TowerAPI.BigInt? { __data["numReads"] }
        /// Count of I/O writes requests sent to the device I/O drivers. These statistics may be cleared at any time.
        public var numWrites: TowerAPI.BigInt? { __data["numWrites"] }
        /// Number of unrecoverable errors reported by the device I/O drivers. Missing
        /// data due to unrecoverable array read errors is filled in on-the-fly using
        /// parity reconstruct (and we attempt to write this data back to the sector(s)
        /// which failed). Any unrecoverable write error results in disabling the disk.
        public var numErrors: TowerAPI.BigInt? { __data["numErrors"] }
        /// Type of Disk - used to differentiate Boot / Cache / Flash / Data (DATA) / Parity
        public var type: GraphQLEnum<TowerAPI.ArrayDiskType> { __data["type"] }
      }

      /// Array.Cach
      ///
      /// Parent Type: `ArrayDisk`
      nonisolated public struct Cach: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.ArrayDisk }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", TowerAPI.PrefixedID.self),
          .field("idx", Int.self),
          .field("name", String?.self),
          .field("device", String?.self),
          .field("status", GraphQLEnum<TowerAPI.ArrayDiskStatus>?.self),
          .field("temp", Int?.self),
          .field("size", TowerAPI.BigInt?.self),
          .field("fsFree", TowerAPI.BigInt?.self),
          .field("fsUsed", TowerAPI.BigInt?.self),
          .field("fsSize", TowerAPI.BigInt?.self),
          .field("fsType", String?.self),
          .field("rotational", Bool?.self),
          .field("numReads", TowerAPI.BigInt?.self),
          .field("numWrites", TowerAPI.BigInt?.self),
          .field("numErrors", TowerAPI.BigInt?.self),
          .field("type", GraphQLEnum<TowerAPI.ArrayDiskType>.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DashboardQuery.Data.Array.Cach.self
        ] }

        public var id: TowerAPI.PrefixedID { __data["id"] }
        /// Array slot number. Parity1 is always 0 and Parity2 is always 29. Array slots
        /// will be 1 - 28. Cache slots are 30 - 53. Flash is 54.
        public var idx: Int { __data["idx"] }
        public var name: String? { __data["name"] }
        public var device: String? { __data["device"] }
        public var status: GraphQLEnum<TowerAPI.ArrayDiskStatus>? { __data["status"] }
        /// Disk temp - will be NaN if array is not started or DISK_NP
        public var temp: Int? { __data["temp"] }
        /// (KB) Disk Size total
        public var size: TowerAPI.BigInt? { __data["size"] }
        /// (KB) Free Size on the FS (Not present on Parity type drive)
        public var fsFree: TowerAPI.BigInt? { __data["fsFree"] }
        /// (KB) Used Size on the FS (Not present on Parity type drive)
        public var fsUsed: TowerAPI.BigInt? { __data["fsUsed"] }
        /// (KB) Total Size of the FS (Not present on Parity type drive)
        public var fsSize: TowerAPI.BigInt? { __data["fsSize"] }
        /// File system type for the disk
        public var fsType: String? { __data["fsType"] }
        /// Is the disk a HDD or SSD.
        public var rotational: Bool? { __data["rotational"] }
        /// Count of I/O read requests sent to the device I/O drivers. These statistics may be cleared at any time.
        public var numReads: TowerAPI.BigInt? { __data["numReads"] }
        /// Count of I/O writes requests sent to the device I/O drivers. These statistics may be cleared at any time.
        public var numWrites: TowerAPI.BigInt? { __data["numWrites"] }
        /// Number of unrecoverable errors reported by the device I/O drivers. Missing
        /// data due to unrecoverable array read errors is filled in on-the-fly using
        /// parity reconstruct (and we attempt to write this data back to the sector(s)
        /// which failed). Any unrecoverable write error results in disabling the disk.
        public var numErrors: TowerAPI.BigInt? { __data["numErrors"] }
        /// Type of Disk - used to differentiate Boot / Cache / Flash / Data (DATA) / Parity
        public var type: GraphQLEnum<TowerAPI.ArrayDiskType> { __data["type"] }
      }
    }

    /// Info
    ///
    /// Parent Type: `Info`
    nonisolated public struct Info: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Info }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("os", Os.self),
        .field("cpu", Cpu.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        DashboardQuery.Data.Info.self
      ] }

      /// Operating system information
      public var os: Os { __data["os"] }
      /// CPU information
      public var cpu: Cpu { __data["cpu"] }

      /// Info.Os
      ///
      /// Parent Type: `InfoOs`
      nonisolated public struct Os: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.InfoOs }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("distro", String?.self),
          .field("release", String?.self),
          .field("uptime", String?.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DashboardQuery.Data.Info.Os.self
        ] }

        /// Linux distribution name
        public var distro: String? { __data["distro"] }
        /// OS release version
        public var release: String? { __data["release"] }
        /// Boot time ISO string
        public var uptime: String? { __data["uptime"] }
      }

      /// Info.Cpu
      ///
      /// Parent Type: `InfoCpu`
      nonisolated public struct Cpu: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.InfoCpu }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("brand", String?.self),
          .field("cores", Int?.self),
          .field("threads", Int?.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DashboardQuery.Data.Info.Cpu.self
        ] }

        /// CPU brand name
        public var brand: String? { __data["brand"] }
        /// Number of CPU cores
        public var cores: Int? { __data["cores"] }
        /// Number of CPU threads
        public var threads: Int? { __data["threads"] }
      }
    }

    /// Metrics
    ///
    /// Parent Type: `Metrics`
    nonisolated public struct Metrics: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Metrics }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("cpu", Cpu?.self),
        .field("memory", Memory?.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        DashboardQuery.Data.Metrics.self
      ] }

      /// Current CPU utilization metrics
      public var cpu: Cpu? { __data["cpu"] }
      /// Current memory utilization metrics
      public var memory: Memory? { __data["memory"] }

      /// Metrics.Cpu
      ///
      /// Parent Type: `CpuUtilization`
      nonisolated public struct Cpu: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.CpuUtilization }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("percentTotal", Double.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DashboardQuery.Data.Metrics.Cpu.self
        ] }

        /// Total CPU load in percent
        public var percentTotal: Double { __data["percentTotal"] }
      }

      /// Metrics.Memory
      ///
      /// Parent Type: `MemoryUtilization`
      nonisolated public struct Memory: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.MemoryUtilization }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("percentTotal", Double.self),
          .field("used", TowerAPI.BigInt.self),
          .field("total", TowerAPI.BigInt.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DashboardQuery.Data.Metrics.Memory.self
        ] }

        /// Memory usage percentage
        public var percentTotal: Double { __data["percentTotal"] }
        /// Used memory in bytes
        public var used: TowerAPI.BigInt { __data["used"] }
        /// Total system memory in bytes
        public var total: TowerAPI.BigInt { __data["total"] }
      }
    }

    /// Docker
    ///
    /// Parent Type: `Docker`
    nonisolated public struct Docker: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Docker }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("containers", [Container].self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        DashboardQuery.Data.Docker.self
      ] }

      /// #### Required Permissions:
      ///
      /// - Action: **READ_ANY**
      /// - Resource: **DOCKER**
      public var containers: [Container] { __data["containers"] }

      /// Docker.Container
      ///
      /// Parent Type: `DockerContainer`
      nonisolated public struct Container: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.DockerContainer }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", TowerAPI.PrefixedID.self),
          .field("state", GraphQLEnum<TowerAPI.ContainerState>.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DashboardQuery.Data.Docker.Container.self
        ] }

        public var id: TowerAPI.PrefixedID { __data["id"] }
        public var state: GraphQLEnum<TowerAPI.ContainerState> { __data["state"] }
      }
    }

    /// Vms
    ///
    /// Parent Type: `Vms`
    nonisolated public struct Vms: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Vms }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("domains", [Domain]?.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        DashboardQuery.Data.Vms.self
      ] }

      public var domains: [Domain]? { __data["domains"] }

      /// Vms.Domain
      ///
      /// Parent Type: `VmDomain`
      nonisolated public struct Domain: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.VmDomain }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", TowerAPI.PrefixedID.self),
          .field("state", GraphQLEnum<TowerAPI.VmState>.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DashboardQuery.Data.Vms.Domain.self
        ] }

        /// The unique identifier for the vm (uuid)
        public var id: TowerAPI.PrefixedID { __data["id"] }
        /// Current domain vm state
        public var state: GraphQLEnum<TowerAPI.VmState> { __data["state"] }
      }
    }

    /// Share
    ///
    /// Parent Type: `Share`
    nonisolated public struct Share: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Share }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("id", TowerAPI.PrefixedID.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        DashboardQuery.Data.Share.self
      ] }

      public var id: TowerAPI.PrefixedID { __data["id"] }
    }
  }
}
