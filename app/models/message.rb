class Message < ApplicationRecord
  belongs_to :user
  belongs_to :room
  after_create_commit { broadcast_append_to room }

  # has_noticed_notifications model_name: 'Notification'
  # has_many :notifications, through: :user, dependent: :destroy
  #
  # after_create_commit :notify_recipient
  # before_destroy :cleanup_notifications
  # has_noticed_notifications model_name: 'Notification'
  #
  # private
  #
  # def notify_recipient
  #   MessageNotification.with(message: self, message: message).deliver_later(message.user)
  # end
  #
  # def cleanup_notifications
  #   notifications_as_message.destroy_all
  # end
end
