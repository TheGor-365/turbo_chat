Rails.application.routes.draw do
  root 'pages#home'

  resources :rooms, only: %i[index show create] do
    resources :messages, only: [:create]
    collection { post :search }
    member do
      post :join
      delete :leave
    end
  end

  get 'rooms/:room_id/messages/:message_id/attachments/:id', to: 'message_attachments#show', as: 'room_message_attachment'\n\n  devise_for :users, controllers: {
    sessions: 'users/sessions',
    registrations: 'users/registrations'
  }

  get 'user/:id', to: 'users#show', as: 'user'
  post 'user/:id/conversation', to: 'users#start_conversation', as: 'start_user_conversation'
end
