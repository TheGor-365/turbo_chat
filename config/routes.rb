Rails.application.routes.draw do
  resources :rooms do
    resources :messages
  end

  root 'rooms#index'

  devise_for :users

  devise_scope :user do
    get 'users', to: 'session/users#new'
  end

  get 'user/:id', to: 'users#show', as: 'user'
end
