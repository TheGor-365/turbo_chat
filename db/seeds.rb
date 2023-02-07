gor = User.create(
  email: 'gor@gor.com',
  password: 'password',
  password_confirmation: 'password',
  role: 'admin'
)

eric = User.create(
  email: 'eric@eric.com',
  password: 'password',
  password_confirmation: 'password',
  role: 'admin'
)

one = User.create(
  email: 'one@one.com',
  password: 'password',
  password_confirmation: 'password'
)

gor.joined_rooms << Room.create(name: 'General', is_private: false)
gor.joined_rooms << Room.create(name: 'Testing', is_private: false)
