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
    registrations: 'users/registrations'
  }

  patch "account/presence", to: "presence_privacy#update", as: :account_presence

  resources :notifications, only: [:index] do
    member { post :read }
    collection { post :read_all }
  end

  post 'user/:id/conversation', to: 'users#start_conversation', as: 'start_user_conversation'
end
