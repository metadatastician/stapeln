// SPDX-License-Identifier: MPL-2.0
// AppRouter.res - Application routing with URL integration

// Route definitions matching App.res pages
type route =
  | LoginView
  | RegisterView
  | NetworkView
  | StackView
  | PipelineView
  | LagoGreyView
  | PortConfigView
  | SecurityView
  | AttackSurfaceView
  | GapAnalysisView
  | SimulationView
  | SettingsView
  | NotFound

// Route to path string
let routeToPath = (route: route): string => {
  switch route {
  | LoginView => "/login"
  | RegisterView => "/register"
  | NetworkView => "/"
  | StackView => "/stack"
  | PipelineView => "/pipeline"
  | LagoGreyView => "/lago-grey"
  | PortConfigView => "/ports"
  | SecurityView => "/security"
  | AttackSurfaceView => "/attack-surface"
  | GapAnalysisView => "/gaps"
  | SimulationView => "/simulation"
  | SettingsView => "/settings"
  | NotFound => "/404"
  }
}

// Path to route
let pathToRoute = (path: string): route => {
  switch path {
  | "/login" => LoginView
  | "/register" => RegisterView
  | "/" => NetworkView
  | "/stack" => StackView
  | "/pipeline" => PipelineView
  | "/lago-grey" => LagoGreyView
  | "/ports" => PortConfigView
  | "/security" => SecurityView
  | "/attack-surface" => AttackSurfaceView
  | "/gaps" => GapAnalysisView
  | "/simulation" => SimulationView
  | "/settings" => SettingsView
  | _ => NotFound
  }
}

// Get current route from browser URL
let getCurrentRoute = (): route => {
  let path = %raw(`window.location.pathname`)
  pathToRoute(path)
}

// Navigate to route (pushState)
let navigateTo = (route: route): unit => {
  let _path = routeToPath(route)
  ignore(%raw(`window.history.pushState(null, "", _path)`))
  %raw(`window.dispatchEvent(new PopStateEvent('popstate'))`)
}

// Replace current route (replaceState)
let replaceRoute = (route: route): unit => {
  let _path = routeToPath(route)
  %raw(`window.history.replaceState(null, "", _path)`)
}

// Go back in history
let goBack = (): unit => {
  %raw(`window.history.back()`)
}

// Go forward in history
let goForward = (): unit => {
  %raw(`window.history.forward()`)
}

// Subscribe to route changes
let onRouteChange = (callback: route => unit): unit => {
  ignore(callback)
  let _handler = %raw(`() => callback(pathToRoute(window.location.pathname))`)
  %raw(`window.addEventListener('popstate', _handler)`)
}

// Route metadata for navigation UI
type routeMeta = {
  route: route,
  label: string,
  icon: string,
  description: string,
}

// Navigation menu items
let navigationItems: array<routeMeta> = [
  {
    route: NetworkView,
    label: "Network",
    icon: "🌐",
    description: "Network topology view",
  },
  {
    route: StackView,
    label: "Stack",
    icon: "📦",
    description: "Vertical stack view",
  },
  {
    route: PipelineView,
    label: "Pipeline",
    icon: "🔧",
    description: "Assembly pipeline designer",
  },
  {
    route: LagoGreyView,
    label: "Lago Grey",
    icon: "🏔️",
    description: "Base image designer",
  },
  {
    route: PortConfigView,
    label: "Ports",
    icon: "🔌",
    description: "Port configuration",
  },
  {
    route: SecurityView,
    label: "Security",
    icon: "🔐",
    description: "Security inspector",
  },
  {
    route: AttackSurfaceView,
    label: "Attack Surface",
    icon: "🎯",
    description: "Attack surface analyzer",
  },
  {
    route: GapAnalysisView,
    label: "Gaps",
    icon: "📊",
    description: "Gap analysis",
  },
  {
    route: SimulationView,
    label: "Simulation",
    icon: "🎮",
    description: "Network simulation",
  },
  {
    route: SettingsView,
    label: "Settings",
    icon: "⚙️",
    description: "Application settings",
  },
]

// Helper: Get route metadata
let getRouteMeta = (route: route): option<routeMeta> => {
  Belt.Array.getBy(navigationItems, item => item.route == route)
}

// Helper: Get route label
let getRouteLabel = (route: route): string => {
  switch getRouteMeta(route) {
  | Some(meta) => meta.label
  | None => "Unknown"
  }
}

// Helper: Get route icon
let getRouteIcon = (route: route): string => {
  switch getRouteMeta(route) {
  | Some(meta) => meta.icon
  | None => "❓"
  }
}
