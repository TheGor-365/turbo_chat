Rails.application.routes.draw do
  root 'pages#home'

  resources :rooms do
    resources :messages
  end

  devise_for :users, controllers: {
    sessions: 'users/sessions',
    registrations: 'users/registrations'
  }

  get 'user/:id', to: 'users#show', as: 'user'
end
