Rails.application.routes.draw do
  root 'pages#home'
  # Railway internal HTTP health probe only. User-facing routes remain HTTPS.
  get "/up", to: "rails/health#show", as: :rails_health_check
  get 'user-avatars/:id', to: 'user_avatars#show', as: 'user_avatar'
  get 'chat-attachments/:id', to: 'chat_attachments#show', as: 'chat_attachment'
  get 'chat-attachments/:id/poster', to: 'chat_attachments#poster', as: 'chat_attachment_poster'

  # Room-scoped, membership-authorized AI scope review. Provider transport is
  # deliberately unavailable until consent, privacy and cost gates are approved.
  get "rooms/:room_id/ai", to: "room_ai_workspaces#show", as: :room_ai_workspace
  post "rooms/:room_id/ai/preview", to: "room_ai_workspaces#preview",
    as: :preview_room_ai_workspace

  post "rooms/:room_id/ai/draft", to: "room_ai_drafts#create", as: :generate_room_ai_draft

  # Personal AI preference; independent of history grants and runtime gates.
  get "account/ai/enablement", to: "account_ai_enablements#show", as: :account_ai_enablement
  patch "account/ai/enablement", to: "account_ai_enablements#update"

  # Private-room member indicators: preference only, never history grants.
  get "rooms/:room_id/ai/member-enablements", to: "room_ai_member_enablements#show", as: :room_ai_member_enablements

  # Independent account-wide writing defaults; not a provider consent grant.
  get "account/ai/writing-preference", to: "account_ai_writing_preferences#show", as: :account_ai_writing_preference
  patch "account/ai/writing-preference", to: "account_ai_writing_preferences#update"
  delete "account/ai/writing-preference", to: "account_ai_writing_preferences#destroy"

  # Room-scoped personal writing preferences, independent of chat consent.
  get "rooms/:room_id/ai/writing-preference", to: "room_ai_writing_preferences#show",
    as: :room_ai_writing_preference
  patch "rooms/:room_id/ai/writing-preference", to: "room_ai_writing_preferences#update"
  delete "rooms/:room_id/ai/writing-preference", to: "room_ai_writing_preferences#destroy"

  # Owner-maintained defaults; personal preferences and author grants remain separate.
  get "rooms/:room_id/ai/shared-writing-preference", to: "room_ai_shared_writing_preferences#show",
    as: :room_ai_shared_writing_preference
  patch "rooms/:room_id/ai/shared-writing-preference", to: "room_ai_shared_writing_preferences#update"

  # Human-authored room context metadata, no automatic provider call.
  get "rooms/:room_id/ai/instructions", to: "room_ai_instructions#show",
    as: :room_ai_instructions
  patch "rooms/:room_id/ai/instructions", to: "room_ai_instructions#update"
  get "rooms/:room_id/ai/instructions/history", to: "room_ai_instructions#history",
    as: :room_ai_instructions_history

  # Read-only room-instruction readiness: one shared versioned source of purpose.
  get "rooms/:room_id/ai/instruction-goal",
    to: "room_ai_instruction_goals#show", as: :room_ai_instruction_goal

  # H3g explicit room-by-room member consent; contextual provider calls are
  # independently disabled until XAI_CONTEXT_REPLIES_ENABLED=1 in development.
  # Per-member goal does not imply consent or authorize AI spending.
  get "rooms/:room_id/ai/conversation-goal",
    to: "room_ai_conversation_goals#show", as: :room_ai_conversation_goal
  patch "rooms/:room_id/ai/conversation-goal",
    to: "room_ai_conversation_goals#update"
  delete "rooms/:room_id/ai/conversation-goal",
    to: "room_ai_conversation_goals#destroy"
  post "rooms/:room_id/ai/answer", to: "room_ai_answers#create",
    as: :generate_room_ai_answer

  post "rooms/:room_id/ai/generation-input-preview",
    to: "room_ai_generation_input_previews#create",
    as: :room_ai_generation_input_preview

  get "rooms/:room_id/ai/context-consent", to: "room_ai_context_consents#show",
    as: :room_ai_context_consent
  patch "rooms/:room_id/ai/context-consent", to: "room_ai_context_consents#update"
  post "rooms/:room_id/ai/reply", to: "room_ai_context_replies#create",
    as: :generate_room_ai_context_reply

  post "rooms/:room_id/ai/task", to: "room_ai_context_tasks#create",
    as: :generate_room_ai_context_task
  # Read-only local preview: same consent + room ACL, no provider/budget call.
  post "rooms/:room_id/ai/context-preview", to: "room_ai_context_previews#create",
    as: :preview_room_ai_context

  # FCC-2b: explicit, metadata-only full-history coverage review with
  # consent-bound pagination. Never an AI generation or source selection API.
  get "rooms/:room_id/ai/coverage-preview/messages/:message_id",
    to: "room_ai_coverage_previews#message", as: :room_ai_coverage_message_preview
  post "rooms/:room_id/ai/evidence-search",
    to: "room_ai_evidence_searches#create", as: :room_ai_evidence_search
  post "rooms/:room_id/ai/evidence-reviews",
    to: "room_ai_evidence_reviews#create", as: :room_ai_evidence_reviews
  post "rooms/:room_id/ai/context-messages", to: "room_ai_context_messages#index",
    as: :room_ai_context_messages
  get "rooms/:room_id/ai/coverage-preview", to: "room_ai_coverage_previews#show",
    as: :room_ai_coverage_preview

  # H4: private, no-provider, non-persistent typed manual review.
  get "rooms/:room_id/ai/deliverable-review", to: "room_ai_deliverable_reviews#new",
    as: :new_room_ai_deliverable_review
  post "rooms/:room_id/ai/deliverable-review", to: "room_ai_deliverable_reviews#create",
    as: :room_ai_deliverable_review

  # H5: explicit-only saved drafts; no autosave, Send or approval.
  resources :rooms, only: [] do
    resources :ai_deliverables, only: %i[index create show update destroy],
      controller: "room_ai_deliverables" do
      get :export, on: :member
    end
  end

  resources :rooms do
    resource :notification_preference, only: :update, controller: "room_notification_preferences"
    member do
      post :read, to: "room_reads#update"
      get :presence, to: "room_presence#show"
    end
    resources :messages do
      resources :reactions, only: %i[create destroy], controller: "message_reactions"
      collection do
        get :sync
        get :search
      end
    end
    collection do
      post :search
      get :inbox
    end
  end

  # Invite-only groups never share public Join routes or canonical 1-to-1 DMs.
  resources :private_groups, only: [:create] do
    member do
      get :membership
      delete :leave
      post :invite
      delete "members/:user_id", action: :remove_member, as: :remove_member
    end
  end
  resources :private_group_invitations, only: [] do
    member do
      post :accept
      post :decline
    end
  end

  post 'rooms/join/:id', to: 'rooms#join', as: 'join_room'
  delete 'rooms/leave/:id', to: 'rooms#leave', as: 'leave_room'

  devise_for :users, controllers: {
    sessions: 'users/sessions',
    registrations: 'users/registrations',
    passwords: 'users/passwords'
  }

  patch "account/presence", to: "presence_privacy#update", as: :account_presence

  resources :notifications, only: [:index] do
    member { post :read }
    collection { post :read_all }
  end

  post 'user/:id/conversation', to: 'users#start_conversation', as: 'start_user_conversation'
end
