// SPDX-License-Identifier: MPL-2.0
// Tour.res - Interactive guided tour of the Stapeln UI
//
// Provides a step-by-step walkthrough highlighting key UI areas with tooltip
// overlays. Fully keyboard navigable: Enter/Space to advance, Escape to skip,
// Shift+Tab/Tab to move between buttons within a step. Tour completion state
// is persisted to localStorage so it only shows automatically on first visit.
//
// Steps cover the core workflow:
//   1. Welcome - introduces Stapeln and the tour
//   2. Navigation tabs - explains the tab bar
//   3. Component Palette - how to add components (Stack view)
//   4. Canvas - the main design area
//   5. Configuration Panel - port configuration and settings
//   6. Simulation Mode - packet tracer simulation
//   7. Stack Deploy - saving and exporting
//
// Usage:
//   <Tour />                    -- auto-shows on first visit
//   Tour.startTour()            -- programmatically trigger via JS
//   just tour                   -- mentions the interactive tour

// ---------------------------------------------------------------------------
// Tour step definition
// ---------------------------------------------------------------------------

// Position hint: where to place the tooltip relative to the target.
// NOTE: declared as its own `type` (not `and`-chained with `tourStep`) —
// the ReScript 12 parser can't resolve a record field whose name is
// identical to a same-recursive-group type it is referencing (pre-existing
// build break, unrelated to this change; see task-2-report.md).
type position =
  | Top
  | Bottom
  | Left
  | Right
  | Center

// Each step has a title, body text, and a target CSS selector used to
// position the tooltip near the relevant UI element. If the target is
// not found in the DOM, the tooltip centres itself on screen.
type tourStep = {
  title: string,
  body: string,
  targetSelector: string,
  // Position hint: where to place the tooltip relative to the target
  position: position,
}

// ---------------------------------------------------------------------------
// Step definitions
// ---------------------------------------------------------------------------

let steps: array<tourStep> = [
  {
    title: "Welcome to Stapeln",
    body: "Stapeln is a visual container stack designer. This tour will walk you through the key areas of the interface. Press Enter to continue or Escape to skip.",
    targetSelector: "",
    position: Center,
  },
  {
    title: "Navigation Tabs",
    body: "Use these tabs to switch between views: Network topology, Stack builder, Pipeline designer, Security inspector, Simulation mode, and more. Each tab focuses on a different aspect of your container stack.",
    targetSelector: ".nav-tabs",
    position: Bottom,
  },
  {
    title: "Component Palette",
    body: "In the Stack view, the left sidebar lists available components: Cerro Torre (build bundles), Svalinn (edge gateway), selur (IPC bridge), and container runtimes. Click any component to add it to your stack.",
    targetSelector: "[aria-label='Component palette']",
    position: Right,
  },
  {
    title: "Design Canvas",
    body: "The central area is your workspace. In the Network view, drag components to position them. Draw connections between components to define your topology. Use Ctrl+Z to undo and Ctrl+Y to redo.",
    targetSelector: "#main-content",
    position: Center,
  },
  {
    title: "Configuration and Ports",
    body: "The Ports tab provides visual port configuration with risk indicators. You can create ephemeral pinholes -- time-limited port openings that automatically close after expiry. Critical ports like SSH are flagged with security warnings.",
    targetSelector: "[role='tab'][aria-selected='true']",
    position: Bottom,
  },
  {
    title: "Simulation Mode",
    body: "The Simulation tab provides a Cisco Packet Tracer-style network simulator. Watch packets flow between nodes, adjust network conditions (latency, drop rate, jitter), and identify bottlenecks. Use the control bar to play, pause, and step through the simulation.",
    targetSelector: ".simulation-mode",
    position: Center,
  },
  {
    title: "Save and Export",
    body: "Use the action buttons in the top-right to import/export designs as JSON, save your stack to the backend, and sign out. Your work is auto-saved every 30 seconds when changes are detected. You are all set -- enjoy building with Stapeln!",
    targetSelector: ".nav-actions",
    position: Bottom,
  },
]

// ---------------------------------------------------------------------------
// LocalStorage key for tour completion tracking
// ---------------------------------------------------------------------------

let storageKey = "stapeln_tour_completed"

// Check whether the tour has been completed previously
let isTourCompleted = (): bool => {
  switch WebAPI.getItem(storageKey)->Nullable.toOption {
  | Some("true") => true
  | _ => false
  }
}

// Mark the tour as completed in localStorage
let markTourCompleted = (): unit => {
  WebAPI.setItem(storageKey, "true")
}

// Reset tour state (allows replaying)
let resetTour = (): unit => {
  WebAPI.removeItem(storageKey)
}

// ---------------------------------------------------------------------------
// DOM measurement helper for positioning
// ---------------------------------------------------------------------------

type domRect = {
  top: float,
  left: float,
  width: float,
  height: float,
  bottom: float,
  right: float,
}

// Query selector and measure bounding rect
let measureTarget = (selector: string): option<domRect> => {
  if selector === "" {
    None
  } else {
    %raw(`
      (function() {
        var el = document.querySelector(selector);
        if (!el) return undefined;
        var r = el.getBoundingClientRect();
        return { top: r.top, left: r.left, width: r.width, height: r.height, bottom: r.bottom, right: r.right };
      })()
    `)
  }
}

// ---------------------------------------------------------------------------
// Component state
// ---------------------------------------------------------------------------

type tourState =
  | Hidden      // Tour not visible
  | Active(int) // Tour visible, showing step N (0-indexed)
  | Completed   // Tour finished this session

// ---------------------------------------------------------------------------
// Tooltip position calculation
// ---------------------------------------------------------------------------

// Compute top/left for the tooltip based on target rect and desired position.
// Falls back to viewport center if no target is found.
let computeTooltipPosition = (
  step: tourStep,
  targetRect: option<domRect>,
): (string, string) => {
  let tooltipWidth = 400.0
  let tooltipHeight = 200.0 // approximate
  let margin = 16.0

  switch targetRect {
  | None =>
    // Center on viewport
    let _top = %raw(`(window.innerHeight / 2 - 100)`)
    let _left = %raw(`(window.innerWidth / 2 - 200)`)
    (Float.toString(_top) ++ "px", Float.toString(_left) ++ "px")
  | Some(rect) =>
    switch step.position {
    | Bottom =>
      let top = rect.bottom +. margin
      let left = Math.max(margin, rect.left +. rect.width /. 2.0 -. tooltipWidth /. 2.0)
      (Float.toString(top) ++ "px", Float.toString(left) ++ "px")
    | Top =>
      let top = rect.top -. tooltipHeight -. margin
      let left = Math.max(margin, rect.left +. rect.width /. 2.0 -. tooltipWidth /. 2.0)
      (Float.toString(top) ++ "px", Float.toString(left) ++ "px")
    | Right =>
      let top = Math.max(margin, rect.top +. rect.height /. 2.0 -. tooltipHeight /. 2.0)
      let left = rect.right +. margin
      (Float.toString(top) ++ "px", Float.toString(left) ++ "px")
    | Left =>
      let top = Math.max(margin, rect.top +. rect.height /. 2.0 -. tooltipHeight /. 2.0)
      let left = rect.left -. tooltipWidth -. margin
      (Float.toString(top) ++ "px", Float.toString(left) ++ "px")
    | Center =>
      let _top = %raw(`(window.innerHeight / 2 - 100)`)
      let _left = %raw(`(window.innerWidth / 2 - 200)`)
      (Float.toString(_top) ++ "px", Float.toString(_left) ++ "px")
    }
  }
}

// ---------------------------------------------------------------------------
// Expose a global function so external callers (e.g. `just tour`) can
// trigger the tour programmatically.
// ---------------------------------------------------------------------------

// This ref is set by the component on mount so the global function can
// dispatch into the React state.
let globalStartRef: ref<option<unit => unit>> = ref(None)

let _registerGlobal: unit = {
  %raw(`
    window.stapelnStartTour = function() {
      // Reset localStorage so the tour shows
      localStorage.removeItem("stapeln_tour_completed");
      // Dispatch if component is mounted
      if (window.__stapelnTourStart) {
        window.__stapelnTourStart();
      } else {
        // Component not mounted yet — set a flag so it auto-starts
        window.__stapelnTourPending = true;
      }
    }
  `)
}

// ---------------------------------------------------------------------------
// React component
// ---------------------------------------------------------------------------

@react.component
let make = () => {
  let totalSteps = Array.length(steps)
  let (tourState, setTourState) = React.useState(() =>
    if isTourCompleted() {
      Hidden
    } else {
      Active(0)
    }
  )

  // Register global start callback
  React.useEffect0(() => {
    let startFn = () => {
      resetTour()
      setTourState(_ => Active(0))
    }
    globalStartRef := Some(startFn)
    // Register on window for global access
    %raw(`window.__stapelnTourStart = startFn`)
    // Check if a start was requested before mount
    let pending: bool = %raw(`!!window.__stapelnTourPending`)
    if pending {
      %raw(`delete window.__stapelnTourPending`)
      startFn()
    }
    Some(() => {
      globalStartRef := None
      %raw(`delete window.__stapelnTourStart`)
    })
  })

  // Advance to next step or complete the tour
  let advance = () => {
    switch tourState {
    | Active(idx) if idx < totalSteps - 1 =>
      setTourState(_ => Active(idx + 1))
    | Active(_) =>
      markTourCompleted()
      setTourState(_ => Completed)
    | _ => ()
    }
  }

  // Go back one step
  let goBack = () => {
    switch tourState {
    | Active(idx) if idx > 0 =>
      setTourState(_ => Active(idx - 1))
    | _ => ()
    }
  }

  // Skip/dismiss the tour entirely
  let skip = () => {
    markTourCompleted()
    setTourState(_ => Completed)
  }

  // Global keyboard handler for the tour overlay.
  // Uses the same %raw addEventListener pattern as App.res (proven to work).
  React.useEffect1(() => {
    switch tourState {
    | Active(_) =>
      let _keyHandler = (e: {..}) => {
        let key: string = e["key"]
        let isTourBtn: bool = %raw(`
          e.target && e.target.classList && e.target.classList.contains("tour-btn")
        `)
        if key === "Escape" {
          e["preventDefault"](.)
          skip()
        } else if (key === "Enter" || key === " ") && !isTourBtn {
          e["preventDefault"](.)
          advance()
        }
      }
      let _: unit = %raw(`document.addEventListener("keydown", _keyHandler)`)
      Some(() => {
        let _: unit = %raw(`document.removeEventListener("keydown", _keyHandler)`)
      })
    | _ => None
    }
  }, [tourState])

  switch tourState {
  | Hidden | Completed => React.null
  | Active(stepIdx) =>
    let step = steps[stepIdx]->Belt.Option.getWithDefault(steps[0]->Belt.Option.getExn)
    let targetRect = measureTarget(step.targetSelector)
    let (topPos, leftPos) = computeTooltipPosition(step, targetRect)
    let isFirst = stepIdx === 0
    let isLast = stepIdx === totalSteps - 1

    // Render: dark overlay + positioned tooltip
    <>
      // Semi-transparent overlay
      <div
        className="tour-overlay"
        onClick={_ => skip()}
        ariaHidden=true
      />

      // Tooltip
      <div
        className="tour-tooltip"
        role="dialog"
        ariaModal=true
        ariaLabel={"Tour step " ++ Int.toString(stepIdx + 1) ++ " of " ++ Int.toString(totalSteps) ++ ": " ++ step.title}
        style={Sx.make(
          ~top=topPos,
          ~left=leftPos,
          (),
        )}
      >
        // Step counter
        <div
          style={Sx.make(
            ~fontSize="11px",
            ~color="#8892a6",
            ~marginBottom="4px",
            ~letterSpacing="0.5px",
            (),
          )}
          ariaHidden=true
        >
          {("Step " ++ Int.toString(stepIdx + 1) ++ " of " ++ Int.toString(totalSteps))->React.string}
        </div>

        <h3> {step.title->React.string} </h3>
        <p> {step.body->React.string} </p>

        // Action bar: progress dots + buttons
        <div className="tour-tooltip-actions">
          // Progress dots
          <div className="tour-progress" ariaHidden=true>
            {Array.mapWithIndex(steps, (idx, _s) => {
              let dotClass = if idx < stepIdx {
                "tour-progress-dot completed"
              } else if idx === stepIdx {
                "tour-progress-dot active"
              } else {
                "tour-progress-dot"
              }
              <div key={Int.toString(idx)} className={dotClass} />
            })->React.array}
          </div>

          // Skip button (not on last step)
          {if !isLast {
            <button
              className="tour-btn tour-btn-secondary"
              onClick={_ => skip()}
              ariaLabel="Skip tour"
            >
              {"Skip"->React.string}
            </button>
          } else {
            React.null
          }}

          // Back button (not on first step)
          {if !isFirst {
            <button
              className="tour-btn tour-btn-secondary"
              onClick={_ => goBack()}
              ariaLabel="Go to previous step"
            >
              {"Back"->React.string}
            </button>
          } else {
            React.null
          }}

          // Next / Finish button
          <button
            className="tour-btn tour-btn-primary"
            onClick={_ => advance()}
            ariaLabel={isLast ? "Finish tour" : "Go to next step"}
            autoFocus=true
          >
            {(isLast ? "Finish" : "Next")->React.string}
          </button>
        </div>
      </div>
    </>
  }
}
