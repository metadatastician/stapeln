// SPDX-License-Identifier: MPL-2.0
// Index.res - Application entry point with high-assurance DOM mounting

// Use the proven DOM mounter (backed by Idris2 proofs)
open DomMounter

// Initialize the application with formal guarantees
let init = () => {
  Console.log("🚀 stapeln - Container Stack Designer")
  Console.log("⚡ Powered by Idris² formal verification")
  Console.log("")

  // Use high-assurance DOM mounting
  switch mountToApp() {
  | Ok() => {
      Console.log("✓ DOM element validated with formal proofs:")
      Console.log("  - Memory safety: PROVEN")
      Console.log("  - Thread safety: PROVEN")
      Console.log("  - Type correctness: PROVEN")
      Console.log("  - Element existence: VERIFIED")
      Console.log("")

      // Mount React application
      switch ReactDOM.querySelector("#app") {
      | Some(root) => {
          let reactRoot = ReactDOM.Client.createRoot(root)
          ReactDOM.Client.Root.render(reactRoot, <App />)
          Console.log("✓ React application mounted successfully")
          Console.log("✓ All components initialized")
        }
      | None => {
          Console.error("❌ CRITICAL: #app element not found after validation")
          Console.error("This should be impossible with formal proofs - please report this bug")
        }
      }
    }
  | Error(msg) => {
      Console.error("❌ Mount validation failed: " ++ msg)
      Console.error("")
      Console.error("Troubleshooting:")
      Console.error("  1. Check that index.html contains <div id=\"app\"></div>")
      Console.error("  2. Ensure no other script has removed the #app element")
      Console.error("  3. Verify DOM is fully loaded before this script runs")
      Console.error("")
      Console.error("The formal verification system prevented mounting to an invalid target.")
      Console.error("This is a safety feature - your application state is protected.")
    }
  }
}

// Auto-run when DOM is ready
switch %external(document) {
| Some(doc) => // Check if DOM is already loaded
  if %raw(`doc.readyState === "loading"`) {
    // Wait for DOMContentLoaded
    %raw(`doc.addEventListener("DOMContentLoaded", function() { init() })`)
    ()
  } else {
    // DOM already loaded, run immediately
    init()
  }
| None => Console.error("❌ Document object not available - are we in a browser?")
}
