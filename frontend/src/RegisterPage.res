// SPDX-License-Identifier: PMPL-1.0-or-later
// RegisterPage.res - Authentication registration form
//
// Renders email/password/confirm-password inputs and dispatches
// RegisterRequested through the TEA message bus. Client-side validation
// (password length, email format, password match) is performed in
// Update.res before the API call is triggered.

open Model
open Msg

@react.component
let make = (~auth: authState, ~isDark: bool, ~dispatch: msg => unit, ~onSwitchToLogin: unit => unit) => {
  // Shared input style matching SettingsPage.res patterns
  let inputStyle = Sx.make(
    ~width="100%",
    ~maxWidth="400px",
    ~padding="0.75rem",
    ~backgroundColor=isDark ? "#1A1A1A" : "#F5F5F5",
    ~color=isDark ? "#FFFFFF" : "#000000",
    ~border=isDark ? "1px solid #CCCCCC" : "1px solid #333333",
    ~borderRadius="4px",
    ~fontSize="1rem",
    ~marginBottom="1rem",
    (),
  )

  let labelStyle = Sx.make(
    ~display="block",
    ~fontWeight="600",
    ~marginBottom="0.5rem",
    ~color=isDark ? "#FFFFFF" : "#000000",
    (),
  )

  let buttonStyle = Sx.make(
    ~padding="0.75rem 1.5rem",
    ~backgroundColor=isDark ? "#66B2FF" : "#0052CC",
    ~color="white",
    ~border="none",
    ~borderRadius="6px",
    ~fontWeight="600",
    ~cursor=auth.authLoading ? "wait" : "pointer",
    ~fontSize="1rem",
    ~width="100%",
    ~maxWidth="400px",
    ~opacity=auth.authLoading ? "0.7" : "1",
    (),
  )

  // Inline validation hints
  let form = auth.registerForm
  let passwordMismatch = form.confirmPassword !== "" && form.password !== form.confirmPassword
  let passwordTooShort = form.password !== "" && String.length(form.password) < 6

  let handleSubmit = (e: ReactEvent.Form.t) => {
    ReactEvent.Form.preventDefault(e)
    dispatch(RegisterRequested)
  }

  <main
    role="main"
    ariaLabel="Create a Stapeln account"
    style={Sx.make(
      ~display="flex",
      ~flexDirection="column",
      ~alignItems="center",
      ~justifyContent="center",
      ~minHeight="100vh",
      ~padding="2rem",
      ~backgroundColor=isDark ? "#000000" : "#FFFFFF",
      ~color=isDark ? "#FFFFFF" : "#000000",
      ~fontFamily="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
      (),
    )}
  >
    <div
      style={Sx.make(
        ~width="100%",
        ~maxWidth="460px",
        ~padding="2rem",
        ~border=isDark ? "2px solid #CCCCCC" : "2px solid #333333",
        ~borderRadius="8px",
        (),
      )}
    >
      <h1
        style={Sx.make(
          ~fontSize="2rem",
          ~fontWeight="700",
          ~marginBottom="0.5rem",
          ~textAlign="center",
          (),
        )}
      >
        {"Stapeln"->React.string}
      </h1>
      <p
        style={Sx.make(
          ~textAlign="center",
          ~marginBottom="2rem",
          ~color=isDark ? "#AAAAAA" : "#666666",
          (),
        )}
      >
        {"Create a new account"->React.string}
      </p>

      // Error display
      {switch auth.authError {
      | Some(error) =>
        <div
          role="alert"
          style={Sx.make(
            ~padding="0.75rem",
            ~marginBottom="1rem",
            ~backgroundColor=isDark ? "#3d1010" : "#fde8e8",
            ~color=isDark ? "#ff6b6b" : "#c53030",
            ~borderRadius="4px",
            ~border=isDark ? "1px solid #ff6b6b" : "1px solid #c53030",
            ~maxWidth="400px",
            ~width="100%",
            (),
          )}
        >
          {error->React.string}
        </div>
      | None => React.null
      }}

      <form onSubmit=handleSubmit>
        <div style={Sx.make(~marginBottom="1rem", ())}>
          <label htmlFor="register-email" style=labelStyle>
            {"Email"->React.string}
          </label>
          <input
            id="register-email"
            type_="email"
            value={form.email}
            onChange={e => {
              let value = ReactEvent.Form.target(e)["value"]
              dispatch(UpdateRegisterEmail(value))
            }}
            placeholder="you@example.com"
            autoComplete="email"
            ariaLabel="Email address"
            ariaRequired=true
            disabled=auth.authLoading
            style=inputStyle
          />
        </div>

        <div style={Sx.make(~marginBottom="1rem", ())}>
          <label htmlFor="register-password" style=labelStyle>
            {"Password"->React.string}
          </label>
          <input
            id="register-password"
            type_="password"
            value={form.password}
            onChange={e => {
              let value = ReactEvent.Form.target(e)["value"]
              dispatch(UpdateRegisterPassword(value))
            }}
            placeholder="At least 6 characters"
            autoComplete="new-password"
            ariaLabel="Password"
            ariaRequired=true
            disabled=auth.authLoading
            style=inputStyle
          />
          {passwordTooShort
            ? <p
                style={Sx.make(
                  ~fontSize="0.85rem",
                  ~color=isDark ? "#ff6b6b" : "#c53030",
                  ~marginTop="-0.5rem",
                  ~marginBottom="0.5rem",
                  (),
                )}
              >
                {"Password must be at least 6 characters"->React.string}
              </p>
            : React.null}
        </div>

        <div style={Sx.make(~marginBottom="1.5rem", ())}>
          <label htmlFor="register-confirm" style=labelStyle>
            {"Confirm password"->React.string}
          </label>
          <input
            id="register-confirm"
            type_="password"
            value={form.confirmPassword}
            onChange={e => {
              let value = ReactEvent.Form.target(e)["value"]
              dispatch(UpdateRegisterConfirm(value))
            }}
            placeholder="Re-enter your password"
            autoComplete="new-password"
            ariaLabel="Confirm password"
            ariaRequired=true
            disabled=auth.authLoading
            style=inputStyle
          />
          {passwordMismatch
            ? <p
                style={Sx.make(
                  ~fontSize="0.85rem",
                  ~color=isDark ? "#ff6b6b" : "#c53030",
                  ~marginTop="-0.5rem",
                  ~marginBottom="0.5rem",
                  (),
                )}
              >
                {"Passwords do not match"->React.string}
              </p>
            : React.null}
        </div>

        <button
          type_="submit"
          disabled=auth.authLoading
          ariaLabel="Create account"
          style=buttonStyle
        >
          {(auth.authLoading ? "Creating account..." : "Create account")->React.string}
        </button>
      </form>

      <p
        style={Sx.make(
          ~textAlign="center",
          ~marginTop="1.5rem",
          ~color=isDark ? "#AAAAAA" : "#666666",
          (),
        )}
      >
        {"Already have an account? "->React.string}
        <button
          onClick={_ => onSwitchToLogin()}
          style={Sx.make(
            ~background="none",
            ~border="none",
            ~color=isDark ? "#66B2FF" : "#0052CC",
            ~cursor="pointer",
            ~fontWeight="600",
            ~padding="0",
            ~fontSize="inherit",
            (),
          )}
        >
          {"Sign in"->React.string}
        </button>
      </p>
    </div>
  </main>
}
