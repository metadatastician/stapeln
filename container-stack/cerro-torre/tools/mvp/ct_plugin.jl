#!/usr/bin/env julia
# SPDX-License-Identifier: MPL-2.0
#
# ct_plugin.jl — Cerro Torre MVP plugin HTTP server.
# Serves a minimal JSON API with:
#   GET /healthz     — health check
#   GET /v1/images   — list images from a JSON file (CT_PLUGIN_IMAGES env)
# Listens on CT_PLUGIN_HOST:CT_PLUGIN_PORT (default 0.0.0.0:8081).

using JSON3
using Sockets

# ---------------------------------------------------------------------------
# Request handling
# ---------------------------------------------------------------------------

"""
    handle_request(method::String, path::String)::Tuple{Int, Dict}

Route an incoming HTTP request and return (status_code, response_body).
"""
function handle_request(method::String, path::String)::Tuple{Int, Any}
    if method == "GET" && path == "/healthz"
        return (200, Dict("status" => "ok"))
    elseif method == "GET" && path == "/v1/images"
        source = get(ENV, "CT_PLUGIN_IMAGES", "tools/mvp/images.json")
        payload = if isfile(source)
            JSON3.read(read(source, String))
        else
            Dict("images" => [])
        end
        return (200, payload)
    else
        return (404, Dict("error" => "not found"))
    end
end

"""
    send_response(client::IO, status::Int, body)

Write a minimal HTTP/1.1 response with JSON body to the client socket.
"""
function send_response(client::IO, status::Int, body)
    status_text = status == 200 ? "OK" : status == 404 ? "Not Found" : "Error"
    json_body = JSON3.write(body)
    response = string(
        "HTTP/1.1 $status $status_text\r\n",
        "Content-Type: application/json\r\n",
        "Content-Length: $(sizeof(json_body))\r\n",
        "\r\n",
        json_body
    )
    write(client, response)
end

"""
    parse_request_line(line::String)::Tuple{String, String}

Extract the HTTP method and path from a request line like "GET /healthz HTTP/1.1".
"""
function parse_request_line(line::String)::Tuple{String, String}
    parts = split(strip(line))
    length(parts) >= 2 || error("malformed request line: $line")
    return (String(parts[1]), String(parts[2]))
end

# ---------------------------------------------------------------------------
# Server loop
# ---------------------------------------------------------------------------

function main()
    host = get(ENV, "CT_PLUGIN_HOST", "0.0.0.0")
    port = parse(Int, get(ENV, "CT_PLUGIN_PORT", "8081"))

    server = listen(Sockets.InetAddr(host, port))
    println("ct_plugin listening on http://$host:$port")

    while true
        client = accept(server)
        @async begin
            try
                # Read request line
                request_line = readline(client)
                method, path = parse_request_line(request_line)

                # Consume remaining headers (until blank line)
                while true
                    header = readline(client)
                    (isempty(strip(header))) && break
                end

                status, body = handle_request(method, path)
                send_response(client, status, body)
            catch e
                @warn "Error handling request" exception=(e, catch_backtrace())
            finally
                close(client)
            end
        end
    end
end

# Run when executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
