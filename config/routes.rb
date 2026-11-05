Rails.application.routes.draw do
  root 'pages#home'
  get 'user-avatars/:id', to: 'user_avatars#show', as: 'user_avatar'
  get 'chat-attachments/:id', to: 'chat_attachments#show', as: 'chat_attachment'

  resources :rooms do
    member do
      post :read, to: "room_reads#update"
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
    end
  end

  post 'rooms/join/:id', to: 'rooms#join', as: 'join_room'
  delete 'rooms/leave/:id', to: 'rooms#leave', as: 'leave_room'

  devise_for :users, controllers: {
    sessions: 'users/sessions',
    registrations: 'users/registrations'
  }

  post 'user/:id/conversation', to: 'users#start_conversation', as: 'start_user_conversation'
end
