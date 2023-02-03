Rails.application.routes.draw do
  get 'users/show'

  resources :rooms do
    resources :messages
  end

  root 'pages#home'

  devise_for :users

  devise_scope :user do
    get 'users', to: 'session/users#new'
  end

  get 'user/:id', to: 'users#show', as: 'user'
end
