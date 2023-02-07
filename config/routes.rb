Rails.application.routes.draw do
  root 'pages#home'

  resources :rooms do
    resources :messages
    collection do
      post :search
    end
  end

  get 'rooms/join/:id', to: 'rooms#join', as: 'join_room'
  get 'rooms/leave/:id', to: 'rooms#leave', as: 'leave_room'

  devise_for :users, controllers: {
    sessions: 'users/sessions',
    registrations: 'users/registrations'
  }

  get 'user/:id', to: 'users#show', as: 'user'
end
