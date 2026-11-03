Rails.application.routes.draw do
  root 'pages#home'
  get 'chat-attachments/:id', to: 'chat_attachments#show', as: 'chat_attachment'

  resources :rooms do
    resources :messages
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

  get 'user/:id', to: 'users#show', as: 'user'
end
