class PagesController < ApplicationController
  # Home is a read-only entry point. Presence is governed by the dedicated
  # connection/session lifecycle; navigating to GET / must not set offline.
  def home
  end
end
