Rails.application.routes.draw do
  root 'pages#home'
  resources :rooms

  devise_for :users
  devise_scope :user do
    get 'users', to: 'session/users#new'
  end
end
