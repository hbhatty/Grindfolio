Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"

  resource :account, only: %i[show update]
  resource :leetcode_verification, only: :create do
    post :verify
  end

  resource :github_activity_update, only: %i[show create]

  get "sign_up", to: "signups#new", as: :sign_up
  post "sign_up", to: "signups#create"
  get "sign_up/success", to: "signups#success", as: :sign_up_success

  get "sign_in", to: "sessions#new", as: :sign_in
  post "sign_in", to: "sessions#create"
  delete "sign_out", to: "sessions#destroy", as: :sign_out

  get "email_verification/resend", to: "email_verification_resends#new", as: :new_email_verification_resend
  post "email_verification/resend", to: "email_verification_resends#create", as: :email_verification_resend
  get "email_verification/resend/accepted", to: "email_verification_resends#accepted", as: :email_verification_resend_accepted

  get "email_verification/:token", to: "email_verifications#show", as: :email_verification
  post "email_verification/:token/confirm", to: "email_verifications#confirm", as: :confirm_email_verification

  get "auth/github/callback", to: "github_connections#callback", as: :github_connection_callback
  get "auth/failure", to: "github_connections#failure", as: :github_connection_failure

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
