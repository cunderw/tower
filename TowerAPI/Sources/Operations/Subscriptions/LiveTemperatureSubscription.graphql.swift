// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct LiveTemperatureSubscription: GraphQLSubscription {
  public static let operationName: String = "LiveTemperature"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"subscription LiveTemperature { systemMetricsTemperature { __typename sensors { __typename type current { __typename value unit } } } }"#
    ))

  public init() {}

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Subscription }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("systemMetricsTemperature", SystemMetricsTemperature?.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      LiveTemperatureSubscription.Data.self
    ] }

    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **INFO**
    public var systemMetricsTemperature: SystemMetricsTemperature? { __data["systemMetricsTemperature"] }

    /// SystemMetricsTemperature
    ///
    /// Parent Type: `TemperatureMetrics`
    nonisolated public struct SystemMetricsTemperature: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.TemperatureMetrics }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("sensors", [Sensor].self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        LiveTemperatureSubscription.Data.SystemMetricsTemperature.self
      ] }

      /// All temperature sensors
      public var sensors: [Sensor] { __data["sensors"] }

      /// SystemMetricsTemperature.Sensor
      ///
      /// Parent Type: `TemperatureSensor`
      nonisolated public struct Sensor: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.TemperatureSensor }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("type", GraphQLEnum<TowerAPI.SensorType>.self),
          .field("current", Current.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          LiveTemperatureSubscription.Data.SystemMetricsTemperature.Sensor.self
        ] }

        /// Type of sensor
        public var type: GraphQLEnum<TowerAPI.SensorType> { __data["type"] }
        /// Current temperature
        public var current: Current { __data["current"] }

        /// SystemMetricsTemperature.Sensor.Current
        ///
        /// Parent Type: `TemperatureReading`
        nonisolated public struct Current: TowerAPI.SelectionSet {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.TemperatureReading }
          @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("value", Double.self),
            .field("unit", GraphQLEnum<TowerAPI.TemperatureUnit>.self),
          ] }
          @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            LiveTemperatureSubscription.Data.SystemMetricsTemperature.Sensor.Current.self
          ] }

          /// Temperature value
          public var value: Double { __data["value"] }
          /// Temperature unit
          public var unit: GraphQLEnum<TowerAPI.TemperatureUnit> { __data["unit"] }
        }
      }
    }
  }
}
