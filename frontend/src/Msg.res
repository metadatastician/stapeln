// SPDX-License-Identifier: MPL-2.0
// Msg.res - TEA Messages (events)

open Model

type msg =
  // Component management
  | AddComponent(componentType, position)
  | RemoveComponent(string)
  | UpdateComponentPosition(string, position)
  | UpdateComponentConfig(string, dict<string>)
  | SelectComponent(option<string>)
  // Connection management
  | AddConnection(string, string) // from, to
  | RemoveConnection(string)
  // Drag and drop
  | StartDragComponent(component, position)
  | StartDragCanvas(position)
  | DragMove(position)
  | DragEnd
  // Canvas operations
  | ZoomIn
  | ZoomOut
  | ResetZoom
  | PanCanvas(position)
  // Validation
  | ValidateStack
  | ValidationResult(validationResult)
  // Export
  | ExportDesignToJson(string) // description
  | ExportToSelurCompose
  | ExportToDockerCompose
  | ExportToPodmanCompose
  | ExportToKubernetesYaml
  | ExportToHelmChart
  // Import
  | TriggerImportDesign
  | ImportDesignSuccess(model)
  | ImportDesignError(string)
  // API communication
  | SaveStack
  | LoadStack(string)
  | StackSaved(Result.t<string, string>)
  | StackLoaded(Result.t<model, string>)
  // Security
  | RunSecurityScan
  | SecurityScanLoading
  | SecurityScanResult(Result.t<JSON.t, string>)
  | RunGapAnalysis
  | GapAnalysisLoading
  | GapAnalysisResult(Result.t<JSON.t, string>)
  // Settings
  | SaveSettings
  | LoadSettings
  | SettingsSaved(Result.t<unit, string>)
  | SettingsLoaded(Result.t<JSON.t, string>)
  // WebSocket real-time (optional — app works with REST only)
  | WsConnect
  | WsDisconnect
  | WsConnectionStateChanged(Socket.connectionState)
  | WsValidate
  | WsValidationResult(JSON.t)
  | WsSecurityScan
  | WsSecurityResult(JSON.t)
  | WsGapAnalysis
  | WsGapResult(JSON.t)
  // Error management (UX Manifesto Rule 4)
  | DismissError(string) // error id
  | RetryImport
  // Undo/redo
  | Undo
  | Redo
  // Auto-save
  | AutoSaveTick
  | MarkClean // called after successful save
  // Authentication
  | LoginRequested
  | LoginSuccess(string) // token
  | LoginError(string)
  | RegisterRequested
  | RegisterSuccess(string) // token
  | RegisterError(string)
  | UpdateLoginEmail(string)
  | UpdateLoginPassword(string)
  | UpdateRegisterEmail(string)
  | UpdateRegisterPassword(string)
  | UpdateRegisterConfirm(string)
  | Logout
  // Pipeline designer
  | Pipeline(PipelineModel.pipelineMsg)
