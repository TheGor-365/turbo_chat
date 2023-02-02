Rails.application.routes.draw do
  devise_for :users
  devise_scope :user do
    get 'users', to: 'session/users#new'
  end
end
