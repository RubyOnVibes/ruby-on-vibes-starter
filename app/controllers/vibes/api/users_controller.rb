module Vibes
  module Api
    class UsersController < Vibes::Api::BaseController
      # POST /vibes/api/users/admins
      # Body: { users: [{ email:, password:, full_name: }, ...] }
      def create_admins
        return render json: { success: false, error: 'Provide users array' }, status: :bad_request unless user_params.is_a?(Array) && user_params.size == 2
        return render json: { success: false, error: 'Admins already seeded' }, status: :bad_request unless User.admins.count < 2

        @created = []
        @errors = []
        User.transaction do
          user_params.each do |user_attrs|
            find_or_create_admin(user_attrs)
          end
        end

        if @errors.any?
          render json: { success: false, created: @created, errors: @errors }, status: :unprocessable_entity
        else
          render json: { success: true, created: @created }, status: :created
        end
      end

      private

      def find_or_create_admin(user_attrs)
        user = User.find_or_initialize_by(email: user_attrs[:email])

        if user.new_record?
          user.full_name = user_attrs[:full_name]
          user.password = user_attrs[:password]
          user.admin = true
          user.save!
        end

        @created << { id: user.id, email: user.email, name: user.name }
      rescue => e
        @errors << { email: user_attrs[:email], error: e.message }
      end

      def user_params
        Array(params[:users]).map do |user_hash|
          {
            email: user_hash[:email] || user_hash['email'],
            password: user_hash[:password] || user_hash['password'],
            full_name: user_hash[:full_name] || user_hash['full_name']
          }
        end
      end
    end
  end
end