# Allow only application-owned scripts and resources.
# Legacy inline layout/user styles and Bootstrap's inline styles currently require
# style-src 'unsafe-inline'. Do not permit inline JavaScript.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.object_src :none
    policy.frame_ancestors :none
    policy.form_action :self
    policy.script_src :self
    policy.style_src :self, :unsafe_inline
    policy.img_src :self, :data, :blob
    policy.font_src :self, :data
    # Turbo/ActionCable uses same-origin WebSockets; explicitly allow ws(s).
    policy.connect_src :self, "ws:", "wss:"
  end
end
