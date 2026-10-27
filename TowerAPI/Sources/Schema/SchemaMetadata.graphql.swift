// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

nonisolated public protocol SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
where Schema == TowerAPI.SchemaMetadata {}

nonisolated public protocol InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
where Schema == TowerAPI.SchemaMetadata {}

nonisolated public protocol MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
where Schema == TowerAPI.SchemaMetadata {}

nonisolated public protocol MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
where Schema == TowerAPI.SchemaMetadata {}

nonisolated public enum SchemaMetadata: ApolloAPI.SchemaMetadata {
  public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

  private static let objectTypeMap: [String: ApolloAPI.Object] = [
    "ApiKey": TowerAPI.Objects.ApiKey,
    "ApiKeyFormSettings": TowerAPI.Objects.ApiKeyFormSettings,
    "ArrayCapacity": TowerAPI.Objects.ArrayCapacity,
    "ArrayDisk": TowerAPI.Objects.ArrayDisk,
    "Capacity": TowerAPI.Objects.Capacity,
    "Config": TowerAPI.Objects.Config,
    "Connect": TowerAPI.Objects.Connect,
    "ConnectSettings": TowerAPI.Objects.ConnectSettings,
    "ContainerHostConfig": TowerAPI.Objects.ContainerHostConfig,
    "ContainerPort": TowerAPI.Objects.ContainerPort,
    "CpuPackages": TowerAPI.Objects.CpuPackages,
    "CpuUtilization": TowerAPI.Objects.CpuUtilization,
    "Disk": TowerAPI.Objects.Disk,
    "Docker": TowerAPI.Objects.Docker,
    "DockerContainer": TowerAPI.Objects.DockerContainer,
    "DockerContainerLogLine": TowerAPI.Objects.DockerContainerLogLine,
    "DockerContainerLogs": TowerAPI.Objects.DockerContainerLogs,
    "DockerMutations": TowerAPI.Objects.DockerMutations,
    "DockerNetwork": TowerAPI.Objects.DockerNetwork,
    "Flash": TowerAPI.Objects.Flash,
    "Info": TowerAPI.Objects.Info,
    "InfoBaseboard": TowerAPI.Objects.InfoBaseboard,
    "InfoCpu": TowerAPI.Objects.InfoCpu,
    "InfoDevices": TowerAPI.Objects.InfoDevices,
    "InfoDisplay": TowerAPI.Objects.InfoDisplay,
    "InfoDisplayCase": TowerAPI.Objects.InfoDisplayCase,
    "InfoGpu": TowerAPI.Objects.InfoGpu,
    "InfoMemory": TowerAPI.Objects.InfoMemory,
    "InfoNetwork": TowerAPI.Objects.InfoNetwork,
    "InfoNetworkInterface": TowerAPI.Objects.InfoNetworkInterface,
    "InfoOs": TowerAPI.Objects.InfoOs,
    "InfoPci": TowerAPI.Objects.InfoPci,
    "InfoSystem": TowerAPI.Objects.InfoSystem,
    "InfoUsb": TowerAPI.Objects.InfoUsb,
    "InfoVersions": TowerAPI.Objects.InfoVersions,
    "LogFile": TowerAPI.Objects.LogFile,
    "LogFileContent": TowerAPI.Objects.LogFileContent,
    "MemoryLayout": TowerAPI.Objects.MemoryLayout,
    "MemoryUtilization": TowerAPI.Objects.MemoryUtilization,
    "Metrics": TowerAPI.Objects.Metrics,
    "Mutation": TowerAPI.Objects.Mutation,
    "Network": TowerAPI.Objects.Network,
    "NetworkMetrics": TowerAPI.Objects.NetworkMetrics,
    "Notification": TowerAPI.Objects.Notification,
    "NotificationCounts": TowerAPI.Objects.NotificationCounts,
    "NotificationOverview": TowerAPI.Objects.NotificationOverview,
    "Notifications": TowerAPI.Objects.Notifications,
    "ParityCheck": TowerAPI.Objects.ParityCheck,
    "ProfileModel": TowerAPI.Objects.ProfileModel,
    "Query": TowerAPI.Objects.Query,
    "Registration": TowerAPI.Objects.Registration,
    "Server": TowerAPI.Objects.Server,
    "Service": TowerAPI.Objects.Service,
    "Settings": TowerAPI.Objects.Settings,
    "Share": TowerAPI.Objects.Share,
    "SsoSettings": TowerAPI.Objects.SsoSettings,
    "TemperatureMetrics": TowerAPI.Objects.TemperatureMetrics,
    "TemperatureSensor": TowerAPI.Objects.TemperatureSensor,
    "UnifiedSettings": TowerAPI.Objects.UnifiedSettings,
    "UnraidArray": TowerAPI.Objects.UnraidArray,
    "UserAccount": TowerAPI.Objects.UserAccount,
    "Vars": TowerAPI.Objects.Vars,
    "VmDomain": TowerAPI.Objects.VmDomain,
    "VmMutations": TowerAPI.Objects.VmMutations,
    "Vms": TowerAPI.Objects.Vms
  ]

  @_spi(Execution) public static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
    objectTypeMap[typename]
  }
}

nonisolated public enum Objects {}
nonisolated public enum Interfaces {}
nonisolated public enum Unions {}
