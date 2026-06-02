// SPDX-License-Identifier: MPL-2.0
// AttackSurfacePage.res - Attack Surface Analyzer panel
//
// Displays a comprehensive view of the stack's attack surface: exposed ports,
// network interfaces, service endpoints, container boundaries, and risk
// categorization. Data sourced from the SecurityInspector scan results and
// an optional dedicated backend endpoint.
//
// MUST-2 task: new frontend panel for the security scanner.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

// Risk level for attack surface entries
type riskLevel =
  | Critical
  | High
  | Medium
  | Low
  | Info

// Represents one entry in the attack surface inventory
type surfaceEntry = {
  id: string,
  category: string, // "port", "endpoint", "interface", "boundary"
  name: string,
  description: string,
  risk: riskLevel,
  component: string, // which stack component owns this
  protocol: option<string>,
  port: option<int>,
  publiclyExposed: bool,
  mitigations: array<string>,
}

// Summary statistics for the header cards
type surfaceSummary = {
  totalEntries: int,
  criticalCount: int,
  highCount: int,
  mediumCount: int,
  lowCount: int,
  publiclyExposed: int,
}

// Component-level state
type state = {
  entries: array<surfaceEntry>,
  summary: surfaceSummary,
  selectedEntry: option<string>,
  filterRisk: option<riskLevel>,
  filterCategory: option<string>,
  searchQuery: string,
  loading: bool,
  error: option<string>,
}

// Messages for internal dispatch
type msg =
  | SelectEntry(string)
  | ClearSelection
  | FilterByRisk(option<riskLevel>)
  | FilterByCategory(option<string>)
  | SetSearchQuery(string)
  | RefreshSurface

// ---------------------------------------------------------------------------
// Initial state
// ---------------------------------------------------------------------------

let emptySummary: surfaceSummary = {
  totalEntries: 0,
  criticalCount: 0,
  highCount: 0,
  mediumCount: 0,
  lowCount: 0,
  publiclyExposed: 0,
}

let init: state = {
  entries: [],
  summary: emptySummary,
  selectedEntry: None,
  filterRisk: None,
  filterCategory: None,
  searchQuery: "",
  loading: false,
  error: None,
}

// ---------------------------------------------------------------------------
// Helpers: risk level utilities
// ---------------------------------------------------------------------------

let riskLabel = (risk: riskLevel): string =>
  switch risk {
  | Critical => "Critical"
  | High => "High"
  | Medium => "Medium"
  | Low => "Low"
  | Info => "Info"
  }

let riskColor = (risk: riskLevel): string =>
  switch risk {
  | Critical => "#d32f2f"
  | High => "#f57c00"
  | Medium => "#fbc02d"
  | Low => "#388e3c"
  | Info => "#1976d2"
  }

let riskRank = (risk: riskLevel): int =>
  switch risk {
  | Critical => 5
  | High => 4
  | Medium => 3
  | Low => 2
  | Info => 1
  }

let categoryIcon = (category: string): string =>
  switch category {
  | "port" => "🔌"
  | "endpoint" => "🌐"
  | "interface" => "🔗"
  | "boundary" => "📦"
  | _ => "🔍"
  }

let categoryLabel = (category: string): string =>
  switch category {
  | "port" => "Exposed Port"
  | "endpoint" => "Service Endpoint"
  | "interface" => "Network Interface"
  | "boundary" => "Container Boundary"
  | _ => "Unknown"
  }

// ---------------------------------------------------------------------------
// Data conversion: build attack surface entries from SecurityInspector state
// ---------------------------------------------------------------------------

// Convert a SecurityInspector.exposedPort into an attack surface entry
let entryFromExposedPort = (ep: SecurityInspector.exposedPort, idx: int): surfaceEntry => {
  let risk = switch ep.risk {
  | "Critical" | "critical" => Critical
  | "High" | "high" => High
  | "Medium" | "medium" => Medium
  | _ => Low
  }
  {
    id: "port-" ++ Int.toString(idx),
    category: "port",
    name: "Port " ++ Int.toString(ep.port) ++ " (" ++ ep.protocol ++ ")",
    description: "Service '" ++
    ep.service ++
    "' exposes port " ++
    Int.toString(ep.port) ++
    " via " ++
    ep.protocol ++ ".",
    risk,
    component: ep.service,
    protocol: Some(ep.protocol),
    port: Some(ep.port),
    publiclyExposed: ep.publiclyAccessible,
    mitigations: ep.publiclyAccessible
      ? [
          "Remove public binding if internal-only",
          "Add firewall rules to restrict source IPs",
          "Route through Svalinn edge gateway",
        ]
      : ["Monitor for unexpected connections"],
  }
}

// Convert a SecurityInspector.vulnerability into an attack surface entry
// (only vulnerabilities that describe reachable surface area)
let entryFromVulnerability = (
  vuln: SecurityInspector.vulnerability,
  idx: int,
): surfaceEntry => {
  let risk = switch vuln.severity {
  | Critical => Critical
  | High => High
  | Medium => Medium
  | Low => Low
  | Info => Info
  }
  let mitigations = switch vuln.fixDescription {
  | Some(desc) => [desc]
  | None => ["Manual review required"]
  }
  {
    id: "vuln-" ++ Int.toString(idx),
    category: "endpoint",
    name: vuln.title,
    description: vuln.description,
    risk,
    component: vuln.affectedComponent,
    protocol: None,
    port: None,
    publiclyExposed: risk == Critical,
    mitigations,
  }
}

// Convert SecurityInspector.securityCheck failures into boundary entries
let entryFromFailedCheck = (
  check: SecurityInspector.securityCheck,
  idx: int,
): option<surfaceEntry> =>
  switch check.result {
  | Fail =>
    Some({
      id: "boundary-" ++ Int.toString(idx),
      category: "boundary",
      name: check.name ++ " (Failed)",
      description: check.description ++ " — " ++ check.details,
      risk: High,
      component: "stack",
      protocol: None,
      port: None,
      publiclyExposed: false,
      mitigations: ["Address the failing check to reduce attack surface"],
    })
  | Warning =>
    Some({
      id: "boundary-" ++ Int.toString(idx),
      category: "boundary",
      name: check.name ++ " (Warning)",
      description: check.description ++ " — " ++ check.details,
      risk: Medium,
      component: "stack",
      protocol: None,
      port: None,
      publiclyExposed: false,
      mitigations: ["Review and improve configuration"],
    })
  | Pass | Unknown => None
  }

// Build full attack surface state from SecurityInspector state
let fromSecurityState = (secState: SecurityInspector.state): state => {
  // Convert exposed ports
  let portEntries =
    secState.exposedPorts
    ->Array.mapWithIndex((idx, ep) => entryFromExposedPort(ep, idx))

  // Convert vulnerabilities to endpoint entries
  let vulnEntries =
    secState.vulnerabilities
    ->Array.mapWithIndex((idx, vuln) => entryFromVulnerability(vuln, idx))

  // Convert failed/warning checks to boundary entries
  let boundaryEntries =
    secState.checks
    ->Array.mapWithIndex((idx, check) => entryFromFailedCheck(check, idx))
    ->Array.reduce([], (acc, opt) =>
      switch opt {
      | Some(entry) => Array.concat(acc, [entry])
      | None => acc
      }
    )

  let allEntries = Array.concatMany([portEntries, vulnEntries, boundaryEntries])

  // Sort by risk (highest first)
  let sorted = Belt.SortArray.stableSortBy(allEntries, (a, b) =>
    riskRank(b.risk) - riskRank(a.risk)
  )

  // Compute summary
  let summary: surfaceSummary = {
    totalEntries: Array.length(sorted),
    criticalCount: Array.reduce(sorted, 0, (acc, e) => e.risk == Critical ? acc + 1 : acc),
    highCount: Array.reduce(sorted, 0, (acc, e) => e.risk == High ? acc + 1 : acc),
    mediumCount: Array.reduce(sorted, 0, (acc, e) => e.risk == Medium ? acc + 1 : acc),
    lowCount: Array.reduce(sorted, 0, (acc, e) =>
      e.risk == Low || e.risk == Info ? acc + 1 : acc
    ),
    publiclyExposed: Array.reduce(sorted, 0, (acc, e) => e.publiclyExposed ? acc + 1 : acc),
  }

  {
    entries: sorted,
    summary,
    selectedEntry: None,
    filterRisk: None,
    filterCategory: None,
    searchQuery: "",
    loading: false,
    error: None,
  }
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

let update = (msg: msg, state: state): state =>
  switch msg {
  | SelectEntry(id) => {...state, selectedEntry: Some(id)}
  | ClearSelection => {...state, selectedEntry: None}
  | FilterByRisk(risk) => {...state, filterRisk: risk}
  | FilterByCategory(cat) => {...state, filterCategory: cat}
  | SetSearchQuery(q) => {...state, searchQuery: q}
  | RefreshSurface => state // Side effect handled by parent
  }

// ---------------------------------------------------------------------------
// View helpers
// ---------------------------------------------------------------------------

// Summary card
let viewSummaryCard = (label: string, count: int, color: string): React.element =>
  <div
    key={label}
    style={Sx.make(
      ~padding="20px",
      ~background="linear-gradient(135deg, #1e2431 0%, #252d3d 100%)",
      ~border="2px solid #2a3142",
      ~borderRadius="12px",
      ~textAlign="center",
      (),
    )}
  >
    <div
      style={Sx.make(
        ~fontSize="36px",
        ~fontWeight="700",
        ~color,
        ~marginBottom="8px",
        (),
      )}
    >
      {Int.toString(count)->React.string}
    </div>
    <div style={Sx.make(~fontSize="13px", ~color="#8892a6", ())}>
      {label->React.string}
    </div>
  </div>

// Risk filter button
let viewRiskFilter = (
  label: string,
  value: option<riskLevel>,
  current: option<riskLevel>,
  color: string,
  dispatch: msg => unit,
): React.element => {
  let isActive = current == value
  <button
    key={label}
    onClick={_ => dispatch(FilterByRisk(value))}
    style={Sx.make(
      ~padding="8px 16px",
      ~background=isActive ? color : "transparent",
      ~color=isActive ? "white" : color,
      ~border="1px solid " ++ color,
      ~borderRadius="6px",
      ~fontSize="12px",
      ~fontWeight="600",
      ~cursor="pointer",
      ~transition="all 0.2s",
      (),
    )}
  >
    {label->React.string}
  </button>
}

// Category filter button
let viewCategoryFilter = (
  label: string,
  icon: string,
  value: option<string>,
  current: option<string>,
  dispatch: msg => unit,
): React.element => {
  let isActive = current == value
  <button
    key={label}
    onClick={_ => dispatch(FilterByCategory(value))}
    style={Sx.make(
      ~padding="8px 16px",
      ~background=isActive
        ? "linear-gradient(135deg, #4a9eff, #7b6cff)"
        : "transparent",
      ~color=isActive ? "white" : "#8892a6",
      ~border=isActive ? "1px solid #4a9eff" : "1px solid #2a3142",
      ~borderRadius="6px",
      ~fontSize="12px",
      ~fontWeight="600",
      ~cursor="pointer",
      ~transition="all 0.2s",
      (),
    )}
  >
    {(icon ++ " " ++ label)->React.string}
  </button>
}

// Single attack surface entry card
let viewEntry = (entry: surfaceEntry, isSelected: bool, dispatch: msg => unit): React.element =>
  <div
    key={entry.id}
    style={Sx.make(
      ~padding="16px 20px",
      ~background=isSelected
        ? "linear-gradient(135deg, #1e2c40 0%, #253550 100%)"
        : "linear-gradient(135deg, #1e2431 0%, #252d3d 100%)",
      ~border=isSelected
        ? "2px solid #4a9eff"
        : "2px solid #2a3142",
      ~borderRadius="12px",
      ~marginBottom="12px",
      ~cursor="pointer",
      ~transition="all 0.2s",
      (),
    )}
    onClick={_ => dispatch(SelectEntry(entry.id))}
  >
    // Header row: category badge + risk badge + public indicator
    <div
      style={Sx.make(
        ~display="flex",
        ~alignItems="center",
        ~gap="8px",
        ~marginBottom="10px",
        ~flexWrap="wrap",
        (),
      )}
    >
      // Category badge
      <span
        style={Sx.make(
          ~padding="4px 10px",
          ~background="#2a3142",
          ~color="#8892a6",
          ~borderRadius="6px",
          ~fontSize="11px",
          ~fontWeight="600",
          (),
        )}
      >
        {(categoryIcon(entry.category) ++ " " ++ categoryLabel(entry.category))->React.string}
      </span>
      // Risk badge
      <span
        style={Sx.make(
          ~padding="4px 12px",
          ~background=riskColor(entry.risk),
          ~color="white",
          ~borderRadius="6px",
          ~fontSize="11px",
          ~fontWeight="700",
          ~textTransform="uppercase",
          (),
        )}
      >
        {riskLabel(entry.risk)->React.string}
      </span>
      // Public exposure indicator
      {entry.publiclyExposed
        ? <span
            style={Sx.make(
              ~padding="4px 8px",
              ~background="rgba(244, 67, 54, 0.2)",
              ~border="1px solid #f44336",
              ~borderRadius="4px",
              ~fontSize="10px",
              ~fontWeight="600",
              ~color="#f44336",
              (),
            )}
          >
            {"PUBLIC"->React.string}
          </span>
        : React.null}
      // Protocol / port tag
      {switch (entry.protocol, entry.port) {
      | (Some(proto), Some(p)) =>
        <span style={Sx.make(~fontSize="11px", ~color="#6b7a90", ())}>
          {(proto ++ ":" ++ Int.toString(p))->React.string}
        </span>
      | (Some(proto), None) =>
        <span style={Sx.make(~fontSize="11px", ~color="#6b7a90", ())}>
          {proto->React.string}
        </span>
      | _ => React.null
      }}
    </div>

    // Title
    <div
      style={Sx.make(
        ~fontSize="15px",
        ~fontWeight="700",
        ~color="#e0e6ed",
        ~marginBottom="6px",
        (),
      )}
    >
      {entry.name->React.string}
    </div>

    // Description
    <div
      style={Sx.make(
        ~fontSize="13px",
        ~color="#8892a6",
        ~lineHeight="1.5",
        ~marginBottom="10px",
        (),
      )}
    >
      {entry.description->React.string}
    </div>

    // Component
    <div style={Sx.make(~fontSize="12px", ~color="#6b7a90", ~marginBottom="10px", ())}>
      {"Component: "->React.string}
      <strong style={Sx.make(~color="#4a9eff", ())}>
        {entry.component->React.string}
      </strong>
    </div>

    // Mitigations (shown when selected)
    {isSelected && Array.length(entry.mitigations) > 0
      ? <div
          style={Sx.make(
            ~padding="12px",
            ~background="rgba(76, 175, 80, 0.1)",
            ~border="1px solid #4caf50",
            ~borderRadius="8px",
            ~marginTop="8px",
            (),
          )}
        >
          <div
            style={Sx.make(
              ~fontSize="12px",
              ~fontWeight="700",
              ~color="#4caf50",
              ~marginBottom="8px",
              (),
            )}
          >
            {"Recommended Mitigations:"->React.string}
          </div>
          <ul
            style={Sx.make(
              ~paddingLeft="20px",
              ~fontSize="12px",
              ~color="#b0b8c4",
              ~lineHeight="1.8",
              ~listStyle="disc",
              (),
            )}
          >
            {entry.mitigations
            ->Array.map(m => <li key={m}> {m->React.string} </li>)
            ->React.array}
          </ul>
        </div>
      : React.null}
  </div>

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

@react.component
let make = (~securityState: option<SecurityInspector.state>=?) => {
  let (state, setState) = React.useState(() =>
    switch securityState {
    | Some(secState) => fromSecurityState(secState)
    | None => init
    }
  )

  // Sync from parent when securityState changes
  React.useEffect1(() => {
    switch securityState {
    | Some(secState) => setState(_ => fromSecurityState(secState))
    | None => ()
    }
    None
  }, [securityState])

  let dispatch = (msg: msg) => {
    setState(prev => update(msg, prev))
  }

  // Filter entries by risk, category, and search query
  let filteredEntries = Array.reduce(state.entries, [], (acc, entry) => {
    let matchesRisk = switch state.filterRisk {
    | Some(r) => entry.risk == r
    | None => true
    }
    let matchesCategory = switch state.filterCategory {
    | Some(c) => entry.category == c
    | None => true
    }
    let matchesSearch =
      state.searchQuery == "" ||
      String.includes(String.toLowerCase(entry.name), String.toLowerCase(state.searchQuery)) ||
      String.includes(
        String.toLowerCase(entry.description),
        String.toLowerCase(state.searchQuery),
      ) ||
      String.includes(String.toLowerCase(entry.component), String.toLowerCase(state.searchQuery))

    if matchesRisk && matchesCategory && matchesSearch {
      Array.concat(acc, [entry])
    } else {
      acc
    }
  })

  let isEmpty = Array.length(state.entries) == 0

  <div
    className="attack-surface-page"
    style={Sx.make(~padding="32px", ~background="#0a0e1a", ~minHeight="100vh", ())}
  >
    // Page header
    <div style={Sx.make(~marginBottom="32px", ())}>
      <h1
        style={Sx.make(
          ~fontSize="32px",
          ~fontWeight="700",
          ~background="linear-gradient(135deg, #ff5722, #ff9800)",
          ~marginBottom="8px",
          (),
        )}
      >
        {"🎯 Attack Surface Analyzer"->React.string}
      </h1>
      <p style={Sx.make(~fontSize="16px", ~color="#8892a6", ())}>
        {"Comprehensive view of exposed ports, service endpoints, network interfaces, and container boundaries"->React.string}
      </p>
    </div>

    // Empty state
    {isEmpty
      ? <div
          style={Sx.make(
            ~padding="60px 40px",
            ~background="linear-gradient(135deg, #1e2431 0%, #252d3d 100%)",
            ~border="2px dashed #2a3f5f",
            ~borderRadius="16px",
            ~textAlign="center",
            (),
          )}
        >
          <div style={Sx.make(~fontSize="48px", ~marginBottom="16px", ())}>
            {"🎯"->React.string}
          </div>
          <h2
            style={Sx.make(
              ~fontSize="20px",
              ~fontWeight="700",
              ~color="#e0e6ed",
              ~marginBottom="12px",
              (),
            )}
          >
            {"No attack surface data yet"->React.string}
          </h2>
          <p
            style={Sx.make(
              ~fontSize="14px",
              ~color="#8892a6",
              ~marginBottom="24px",
              ~lineHeight="1.6",
              (),
            )}
          >
            {"Run a security scan first to populate the attack surface analysis. The analyzer will map exposed ports, service endpoints, network interfaces, and container boundaries across your entire stack."->React.string}
          </p>
        </div>
      : React.null}

    // Main content (only shown when data exists)
    {isEmpty
      ? React.null
      : <>
          // Summary cards
          <div
            style={Sx.make(
              ~display="grid",
              ~gridTemplateColumns="repeat(4, 1fr)",
              ~gap="16px",
              ~marginBottom="32px",
              (),
            )}
          >
            {viewSummaryCard("Total Surface", state.summary.totalEntries, "#4a9eff")}
            {viewSummaryCard("Critical", state.summary.criticalCount, "#d32f2f")}
            {viewSummaryCard("High Risk", state.summary.highCount, "#f57c00")}
            {viewSummaryCard("Publicly Exposed", state.summary.publiclyExposed, "#f44336")}
          </div>

          // Search bar
          <div
            style={Sx.make(
              ~marginBottom="16px",
              (),
            )}
          >
            <input
              type_="text"
              placeholder="Search by name, description, or component..."
              value={state.searchQuery}
              onChange={e => {
                let value = ReactEvent.Form.target(e)["value"]
                dispatch(SetSearchQuery(value))
              }}
              style={Sx.make(
                ~width="100%",
                ~padding="12px 16px",
                ~background="#1e2431",
                ~border="2px solid #2a3142",
                ~borderRadius="8px",
                ~color="#e0e6ed",
                ~fontSize="14px",
                (),
              )}
            />
          </div>

          // Filter toolbar
          <div
            style={Sx.make(
              ~display="flex",
              ~justifyContent="space-between",
              ~alignItems="center",
              ~padding="16px",
              ~background="linear-gradient(135deg, #1e2431 0%, #252d3d 100%)",
              ~border="2px solid #2a3142",
              ~borderRadius="12px",
              ~marginBottom="24px",
              ~flexWrap="wrap",
              ~gap="12px",
              (),
            )}
          >
            // Risk filters
            <div style={Sx.make(~display="flex", ~gap="8px", ~flexWrap="wrap", ())}>
              {viewRiskFilter("All", None, state.filterRisk, "#4a9eff", dispatch)}
              {viewRiskFilter("Critical", Some(Critical), state.filterRisk, "#d32f2f", dispatch)}
              {viewRiskFilter("High", Some(High), state.filterRisk, "#f57c00", dispatch)}
              {viewRiskFilter("Medium", Some(Medium), state.filterRisk, "#fbc02d", dispatch)}
              {viewRiskFilter("Low", Some(Low), state.filterRisk, "#388e3c", dispatch)}
            </div>

            // Category filters
            <div style={Sx.make(~display="flex", ~gap="8px", ~flexWrap="wrap", ())}>
              {viewCategoryFilter("All", "🔍", None, state.filterCategory, dispatch)}
              {viewCategoryFilter("Ports", "🔌", Some("port"), state.filterCategory, dispatch)}
              {viewCategoryFilter("Endpoints", "🌐", Some("endpoint"), state.filterCategory, dispatch)}
              {viewCategoryFilter("Boundaries", "📦", Some("boundary"), state.filterCategory, dispatch)}
            </div>
          </div>

          // Results count
          <div
            style={Sx.make(
              ~fontSize="13px",
              ~color="#6b7a90",
              ~marginBottom="16px",
              (),
            )}
          >
            {"Showing "->React.string}
            <strong style={Sx.make(~color="#e0e6ed", ())}>
              {Int.toString(Array.length(filteredEntries))->React.string}
            </strong>
            {" of "->React.string}
            <strong style={Sx.make(~color="#e0e6ed", ())}>
              {Int.toString(state.summary.totalEntries)->React.string}
            </strong>
            {" attack surface entries"->React.string}
          </div>

          // Entry list
          <div>
            {Array.length(filteredEntries) > 0
              ? filteredEntries
                ->Array.map(entry =>
                  viewEntry(entry, state.selectedEntry == Some(entry.id), dispatch)
                )
                ->React.array
              : <div
                  style={Sx.make(
                    ~padding="40px",
                    ~background="linear-gradient(135deg, #1e2431 0%, #252d3d 100%)",
                    ~border="2px solid #2a3142",
                    ~borderRadius="12px",
                    ~textAlign="center",
                    (),
                  )}
                >
                  <div style={Sx.make(~fontSize="32px", ~marginBottom="12px", ())}>
                    {"🔎"->React.string}
                  </div>
                  <div
                    style={Sx.make(
                      ~fontSize="16px",
                      ~fontWeight="600",
                      ~color="#8892a6",
                      (),
                    )}
                  >
                    {"No entries match the current filters"->React.string}
                  </div>
                </div>}
          </div>

          // Intelligence footer
          <div
            style={Sx.make(
              ~marginTop="32px",
              ~padding="20px",
              ~background="rgba(255, 87, 34, 0.1)",
              ~border="2px solid #ff5722",
              ~borderRadius="12px",
              (),
            )}
          >
            <h4
              style={Sx.make(
                ~fontSize="16px",
                ~fontWeight="700",
                ~color="#ff5722",
                ~marginBottom="12px",
                (),
              )}
            >
              {"🎯 Attack Surface Intelligence"->React.string}
            </h4>
            <p style={Sx.make(~fontSize="13px", ~color="#b0b8c4", ~lineHeight="1.8", ())}>
              {"Attack surface data aggregated from the security scanner, miniKanren reasoning engine, and container boundary analysis. Each entry includes risk categorization and actionable mitigations. Publicly exposed surfaces are flagged for immediate review. All findings logged to VeriSimDB for compliance audit."->React.string}
            </p>
          </div>
        </>}
  </div>
}
