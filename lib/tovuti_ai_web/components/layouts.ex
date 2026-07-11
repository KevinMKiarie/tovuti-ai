defmodule TovutiAiWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use TovutiAiWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Full-screen light auth layout. White background + multi-hue gradient mesh +
  realistic ghost chat (light-mode) + backdrop-blur frosted layer + white modal card.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <div style="min-height:100vh;width:100%;position:relative;background:#fafafa;overflow:hidden;font-family:'Sora',system-ui,sans-serif;">

      <%!-- ① Static multi-hue gradient mesh (bottom layer) --%>
      <div style="position:fixed;inset:0;z-index:0;pointer-events:none;background-image:radial-gradient(ellipse 65% 55% at 12% 38%,rgba(139,92,246,0.22) 0%,transparent 100%),radial-gradient(ellipse 58% 48% at 84% 18%,rgba(6,182,212,0.18) 0%,transparent 100%),radial-gradient(ellipse 50% 44% at 52% 88%,rgba(59,130,246,0.14) 0%,transparent 100%),radial-gradient(ellipse 42% 38% at 92% 72%,rgba(236,72,153,0.11) 0%,transparent 100%),radial-gradient(ellipse 48% 40% at 4% 82%,rgba(20,184,166,0.13) 0%,transparent 100%);"></div>

      <%!-- ② Drifting orbs on top of mesh --%>
      <div class="auth-orb-a" style="position:absolute;z-index:0;pointer-events:none;width:680px;height:680px;border-radius:50%;top:-200px;right:-120px;background:radial-gradient(circle,rgba(139,92,246,0.16) 0%,transparent 68%);"></div>
      <div class="auth-orb-b" style="position:absolute;z-index:0;pointer-events:none;width:580px;height:580px;border-radius:50%;bottom:-160px;left:-80px;background:radial-gradient(circle,rgba(6,182,212,0.14) 0%,transparent 68%);"></div>
      <div class="auth-orb-c" style="position:absolute;z-index:0;pointer-events:none;width:400px;height:400px;border-radius:50%;top:55%;left:48%;background:radial-gradient(circle,rgba(236,72,153,0.09) 0%,transparent 68%);"></div>

      <%!-- ③ Ghost chat (light-mode replica, moderate opacity — blurred by the backdrop layer above) --%>
      <div class="auth-ghost" aria-hidden="true">
        <%!-- Sidebar --%>
        <div style="width:200px;border-right:1px solid rgba(0,0,0,0.06);background:rgba(255,255,255,0.7);padding:18px 12px;display:flex;flex-direction:column;gap:10px;flex-shrink:0;">
          <%!-- New chat button bar --%>
          <div style="height:30px;border-radius:8px;background:rgba(0,0,0,0.06);width:100%;margin-bottom:6px;"></div>
          <%!-- Section label --%>
          <div style="height:5px;border-radius:3px;background:rgba(0,0,0,0.15);width:30%;margin-bottom:4px;"></div>
          <%!-- Thread list items --%>
          <div style="height:7px;border-radius:4px;background:rgba(0,0,0,0.12);width:88%;"></div>
          <div style="height:7px;border-radius:4px;background:rgba(0,0,0,0.08);width:72%;"></div>
          <div style="height:7px;border-radius:4px;background:rgba(0,0,0,0.08);width:92%;"></div>
          <div style="height:7px;border-radius:4px;background:rgba(0,0,0,0.08);width:65%;"></div>
          <div style="height:7px;border-radius:4px;background:rgba(0,0,0,0.08);width:80%;"></div>
          <div style="height:7px;border-radius:4px;background:rgba(0,0,0,0.08);width:58%;"></div>
          <div style="flex:1;"></div>
          <%!-- Settings row --%>
          <div style="height:28px;border-radius:8px;background:rgba(0,0,0,0.05);width:100%;"></div>
        </div>
        <%!-- Main chat area --%>
        <div style="flex:1;padding:48px 72px;display:flex;flex-direction:column;gap:32px;overflow:hidden;background:rgba(250,250,250,0.5);">
          <%!-- User bubble --%>
          <div style="display:flex;justify-content:flex-end;">
            <div style="background:rgba(0,0,0,0.07);border-radius:20px 20px 4px 20px;padding:12px 18px;max-width:300px;display:flex;flex-direction:column;gap:6px;">
              <div style="height:6px;border-radius:3px;background:rgba(0,0,0,0.25);width:200px;"></div>
            </div>
          </div>
          <%!-- AI reply --%>
          <div style="display:flex;flex-direction:column;gap:8px;max-width:500px;">
            <div style="display:flex;align-items:center;gap:8px;margin-bottom:4px;">
              <div style="width:18px;height:18px;border-radius:50%;background:linear-gradient(135deg,#8b5cf6,#14b8a6);flex-shrink:0;"></div>
              <div style="height:5px;border-radius:3px;background:rgba(0,0,0,0.12);width:40px;"></div>
            </div>
            <div style="height:6px;border-radius:3px;background:rgba(0,0,0,0.1);width:100%;"></div>
            <div style="height:6px;border-radius:3px;background:rgba(0,0,0,0.08);width:91%;"></div>
            <div style="height:6px;border-radius:3px;background:rgba(0,0,0,0.07);width:83%;"></div>
          </div>
          <%!-- User bubble --%>
          <div style="display:flex;justify-content:flex-end;">
            <div style="background:rgba(0,0,0,0.07);border-radius:20px 20px 4px 20px;padding:12px 18px;">
              <div style="height:6px;border-radius:3px;background:rgba(0,0,0,0.22);width:150px;"></div>
            </div>
          </div>
          <%!-- AI reply --%>
          <div style="display:flex;flex-direction:column;gap:8px;max-width:480px;">
            <div style="display:flex;align-items:center;gap:8px;margin-bottom:4px;">
              <div style="width:18px;height:18px;border-radius:50%;background:linear-gradient(135deg,#8b5cf6,#14b8a6);flex-shrink:0;"></div>
              <div style="height:5px;border-radius:3px;background:rgba(0,0,0,0.12);width:40px;"></div>
            </div>
            <div style="height:6px;border-radius:3px;background:rgba(0,0,0,0.1);width:100%;"></div>
            <div style="height:6px;border-radius:3px;background:rgba(0,0,0,0.08);width:86%;"></div>
            <div style="height:6px;border-radius:3px;background:rgba(0,0,0,0.08);width:94%;"></div>
            <div style="height:6px;border-radius:3px;background:rgba(0,0,0,0.07);width:72%;"></div>
          </div>
          <%!-- Input bar at bottom --%>
          <div style="margin-top:auto;border:1px solid rgba(0,0,0,0.08);border-radius:16px;padding:14px 16px;background:rgba(255,255,255,0.8);">
            <div style="height:6px;border-radius:3px;background:rgba(0,0,0,0.07);width:45%;margin-bottom:12px;"></div>
            <div style="display:flex;justify-content:flex-end;">
              <div style="width:28px;height:28px;border-radius:50%;background:rgba(0,0,0,0.12);"></div>
            </div>
          </div>
        </div>
      </div>

      <%!-- ④ Frosted-glass backdrop — blurs everything (mesh + orbs + ghost) behind the modal --%>
      <div class="auth-backdrop"></div>

      <%!-- ⑤ White modal card --%>
      <div
        style="position:relative;z-index:10;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px;"
      >
        <div
          class="auth-card-enter"
          style="width:100%;max-width:412px;background:rgba(255,255,255,0.94);border:1px solid rgba(0,0,0,0.07);border-radius:22px;padding:40px;box-shadow:0 2px 8px rgba(0,0,0,0.04),0 8px 28px rgba(0,0,0,0.07),0 32px 72px rgba(0,0,0,0.06);"
        >
          <%!-- Wordmark --%>
          <div style="display:flex;align-items:center;gap:10px;margin-bottom:32px;">
            <div style="width:28px;height:28px;border-radius:50%;background:linear-gradient(135deg,#8b5cf6,#06b6d4,#14b8a6);flex-shrink:0;box-shadow:0 2px 8px rgba(139,92,246,0.35);"></div>
            <span style="font-size:18px;font-weight:300;letter-spacing:0.1em;color:rgba(0,0,0,0.78);">tovuti</span>
          </div>

          <%!-- Flash messages --%>
          <%= if msg = Phoenix.Flash.get(@flash, :error) do %>
            <div style="background:rgba(220,38,38,0.06);border:1px solid rgba(220,38,38,0.18);border-radius:10px;padding:11px 14px;font-size:13px;color:#b91c1c;margin-bottom:20px;line-height:1.5;">
              {msg}
            </div>
          <% end %>
          <%= if msg = Phoenix.Flash.get(@flash, :info) do %>
            <div style="background:rgba(37,99,235,0.06);border:1px solid rgba(37,99,235,0.18);border-radius:10px;padding:11px 14px;font-size:13px;color:#1d4ed8;margin-bottom:20px;line-height:1.5;">
              {msg}
            </div>
          <% end %>

          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
