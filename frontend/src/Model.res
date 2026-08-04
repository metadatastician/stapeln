// SPDX-License-Identifier: MPL-2.0
// Model.res - TEA Model (application state)

type componentType =
  | CerroTorre // Container builder (.ctp bundles)
  | LagoGrey // Base image designer (Alpine/Chainguard alternative)
  | Svalinn // Edge gateway
  | Selur // IPC bridge
  | Vordr // Runtime/orchestrator
  | Podman // Container runtime
  | Docker // Container runtime
  | Nerdctl // Container runtime
  | Volume // Persistent storage
  | Network // Networking

type position = {
  x: float,
  y: float,
}

type component = {
  id: string,
  componentType: componentType,
  position: position,
  config: dict<string>, // Component-specific configuration
}

type connection = {
  id: string,
  from: string, // Component ID
  to: string, // Component ID
}

type dragState =
  | NotDragging
  | DraggingComponent(component)
  | DraggingCanvas(position)

// Authentication state for login/register flow
type loginForm = {
  email: string,
  password: string,
}

type registerForm = {
  email: string,
  password: string,
  confirmPassword: string,
}

type authState = {
  isAuthenticated: bool,
  currentEmail: option<string>,
  authError: option<string>,
  authLoading: bool,
  loginForm: loginForm,
  registerForm: registerForm,
}

let defaultLoginForm: loginForm = {
  email: "",
  password: "",
}

let defaultRegisterForm: registerForm = {
  email: "",
  password: "",
  confirmPassword: "",
}

let defaultAuthState: authState = {
  isAuthenticated: false,
  currentEmail: None,
  authError: None,
  authLoading: false,
  loginForm: defaultLoginForm,
  registerForm: defaultRegisterForm,
}

// Check localStorage for an existing auth token on startup
let initAuthState = (): authState => {
  switch ApiClient.getToken() {
  | Some(_) => {...defaultAuthState, isAuthenticated: true}
  | None => defaultAuthState
  }
}

// Settings stored in the model for backend persistence
type settingsConfig = {
  theme: string, // "dark" or "light"
  defaultRuntime: string, // "podman", "docker", or "nerdctl"
  autoSave: bool,
  backendUrl: string,
}

let defaultSettingsConfig: settingsConfig = {
  theme: "dark",
  defaultRuntime: "podman",
  autoSave: false,
  backendUrl: "/api",
}

// Snapshot of undoable state (components + connections only)
type snapshot = {
  components: array<component>,
  connections: array<connection>,
}

// Maximum undo history depth
let maxUndoDepth = 50

type rec model = {
  components: array<component>,
  connections: array<connection>,
  selectedComponent: option<string>,
  dragState: dragState,
  canvasOffset: position,
  zoomLevel: float,
  validationResult: option<validationResult>,
  // Security and gap analysis state from backend
  securityState: option<SecurityInspector.state>,
  gapState: option<GapAnalysis.state>,
  securityLoading: bool,
  gapLoading: bool,
  currentStackId: option<int>,
  // User-facing identity for the saved stack (sent to the backend on save
  // so `derive_name` doesn't fall through to the literal "stapeln-stack"
  // for every stack — see App.res's `serializeForApi`)
  stackName: string,
  stackDescription: string,
  // Settings
  settings: settingsConfig,
  // WebSocket state (optional — None means REST-only mode)
  wsState: Socket.connectionState,
  // Undo/redo history
  undoStack: array<snapshot>,
  redoStack: array<snapshot>,
  // Dirty tracking for auto-save
  isDirty: bool,
  lastSavedAt: option<float>, // Date.now() timestamp
  // Active user-facing errors (conversational style, UX Manifesto Rule 4)
  activeErrors: array<userError>,
  // Authentication
  auth: authState,
}

// A user-facing error with optional fix action
and userError = {
  id: string,
  title: string,
  reason: option<string>,
  severity: ConversationalError.severity,
  fixLabel: option<string>,
  // Fix actions are dispatched as messages, not stored in model
}

and validationResult = {
  valid: bool,
  errors: array<string>,
  warnings: array<string>,
}

let initialModel = {
  components: [],
  connections: [],
  selectedComponent: None,
  dragState: NotDragging,
  canvasOffset: {x: 0.0, y: 0.0},
  zoomLevel: 1.0,
  validationResult: None,
  securityState: None,
  gapState: None,
  securityLoading: false,
  gapLoading: false,
  currentStackId: None,
  stackName: "",
  stackDescription: "",
  settings: defaultSettingsConfig,
  wsState: Disconnected,
  undoStack: [],
  redoStack: [],
  isDirty: false,
  lastSavedAt: None,
  activeErrors: [],
  auth: initAuthState(),
}

// Helper functions

let generateId = () => {
  // Simple UUID v4 generation
  let chars = "0123456789abcdef"
  let uuid = ref("")
  for i in 0 to 35 {
    let idx = Float.toInt(Math.random() *. 16.0)
    let char = String.charAt(chars, idx)
    uuid := uuid.contents ++ char
    if i == 7 || i == 12 || i == 17 || i == 22 {
      uuid := uuid.contents ++ "-"
    }
  }
  uuid.contents
}

let findComponent = (model: model, id: string): option<component> => {
  Array.getBy(model.components, c => c.id == id)
}

// Take a snapshot of the current undoable state
let takeSnapshot = (model: model): snapshot => {
  components: model.components,
  connections: model.connections,
}

// Push a snapshot onto the undo stack (call BEFORE making the change)
let pushUndo = (model: model): model => {
  let snap = takeSnapshot(model)
  let stack = Array.concat(model.undoStack, [snap])
  // Trim to max depth
  let trimmed = if Array.length(stack) > maxUndoDepth {
    Array.slice(stack, ~offset=Array.length(stack) - maxUndoDepth, ~len=maxUndoDepth)
  } else {
    stack
  }
  {...model, undoStack: trimmed, redoStack: [], isDirty: true}
}

// Check if undo/redo are available
let canUndo = (model: model): bool => Array.length(model.undoStack) > 0
let canRedo = (model: model): bool => Array.length(model.redoStack) > 0

let componentTypeToString = (ct: componentType): string => {
  switch ct {
  | CerroTorre => "Cerro Torre"
  | LagoGrey => "Lago Grey"
  | Svalinn => "Svalinn"
  | Selur => "selur"
  | Vordr => "Vörðr"
  | Podman => "Podman"
  | Docker => "Docker"
  | Nerdctl => "nerdctl"
  | Volume => "Volume"
  | Network => "Network"
  }
}
