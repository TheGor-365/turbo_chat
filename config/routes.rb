Rails.application.routes.draw do
  root 'pages#home'
  get 'user-avatars/:id', to: 'user_avatars#show', as: 'user_avatar'
  get 'chat-attachments/:id', to: 'chat_attachments#show', as: 'chat_attachment'
  get 'chat-attachments/:id/poster', to: 'chat_attachments#poster', as: 'chat_attachment_poster'

  # Room-scoped, membership-authorized AI scope review. Provider transport is
  # deliberately unavailable until consent, privacy and cost gates are approved.
  get "rooms/:room_id/ai", to: "room_ai_workspaces#show", as: :room_ai_workspace
  post "rooms/:room_id/ai/preview", to: "room_ai_workspaces#preview",
    as: :preview_room_ai_workspace

  post "rooms/:room_id/ai/draft", to: "room_ai_drafts#create", as: :generate_room_ai_draft

  # H3g explicit room-by-room member consent; contextual provider calls are
  # independently disabled until XAI_CONTEXT_REPLIES_ENABLED=1 in development.
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
