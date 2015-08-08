# Copyright (C) 2015 MongoDB, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Mongo
  class BulkWrite

    # Defines behaviour around transformations.
    #
    # @api private
    #
    # @since 2.1.0
    module Transformable

      # The delete many model constant.
      #
      # @since 2.1.0
      DELETE_MANY = :delete_many.freeze

      # The delete one model constant.
      #
      # @since 2.1.0
      DELETE_ONE = :delete_one.freeze

      # The insert one model constant.
      #
      # @since 2.1.0
      INSERT_ONE = :insert_one.freeze

      # The update many model constant.
      #
      # @since 2.1.0
      UPDATE_MANY = :update_many.freeze

      # The update one model constant.
      #
      # @since 2.1.0
      UPDATE_ONE = :update_one.freeze

      # Document mappers from the bulk api input into proper commands.
      #
      # @since 2.1.0
      MAPPERS = {
        DELETE_MANY => ->(doc){{ q: doc[:filter], limit: 0 }},
        DELETE_ONE  => ->(doc){{ q: doc[:filter], limit: 1 }},
        INSERT_ONE  => ->(doc){ doc },
        UPDATE_MANY  => ->(doc){
          { q: doc[:filter], u: doc[:update], multi: true, upsert: doc.fetch(:upsert, false) }
        },
        UPDATE_ONE  => ->(doc){
          { q: doc[:filter], u: doc[:update], multi: false, upsert: doc.fetch(:upsert, false) }
        }
      }.freeze

      private

      def transform(name, document)
        validate(name, document)
        MAPPERS[name].call(document)
      end
    end
  end
end
