# frozen_string_literal: true
# rubocop:todo all

# Copyright (C) 2014-2020 MongoDB Inc.
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

require 'mongo/operation/shared/result/aggregatable'
require 'mongo/operation/shared/result/use_legacy_error_parser'

module Mongo
  module Operation

    # Result wrapper for wire protocol replies.
    #
    # An operation has zero or one replies. The only operations producing zero
    # replies are unacknowledged writes; all other operations produce one reply.
    # This class provides an object that can be operated on (for example, to
    # check whether an operation succeeded) even when the operation did not
    # produce a reply (in which case it is assumed to have succeeded).
    #
    # @since 2.0.0
    # @api semiprivate
    class NullResult < Result
      def initialize
        super(nil)
      end

      # Is the result acknowledged?
      #
      # @note On MongoDB 2.6 and higher all writes are acknowledged since the
      #   driver uses write commands for all write operations. On 2.4 and
      #   lower, the result is acknowledged if the GLE has been executed after
      #   the command. If not, no replies will be specified. Reads will always
      #   return true here since a replies is always provided.
      #
      # @return [ true, false ] If the result is acknowledged.
      #
      # @since 2.0.0
      # @api public
      def acknowledged?
        true
      end

      # Whether the result contains cursor_id
      #
      # @return [ true, false ] If the result contains cursor_id.
      #
      # @api private
      def has_cursor_id?
        false
      end

      # Get the cursor id if the response is acknowledged.
      #
      # @note Cursor ids of 0 indicate there is no cursor on the server.
      #
      # @example Get the cursor id.
      #   result.cursor_id
      #
      # @return [ Integer ] The cursor id.
      #
      # @since 2.0.0
      # @api private
      def cursor_id
        0
      end

      # Get the namespace of the cursor. The method should be defined in
      # result classes where 'ns' is in the server response.
      #
      # @return [ Nil ]
      #
      # @since 2.0.0
      # @api private
      def namespace
        nil
      end

      # Get the documents in the result.
      #
      # @example Get the documents.
      #   result.documents
      #
      # @return [ Array<BSON::Document> ] The documents.
      #
      # @since 2.0.0
      # @api public
      def documents
        []
      end

      # Iterate over the documents in the replies.
      #
      # @example Iterate over the documents.
      #   result.each do |doc|
      #     p doc
      #   end
      #
      # @return [ Enumerator ] The enumerator.
      #
      # @yieldparam [ BSON::Document ] Each document in the result.
      #
      # @since 2.0.0
      # @api public
      def each(&block)
        documents.each(&block)
      end

      # Get the pretty formatted inspection of the result.
      #
      # @example Inspect the result.
      #   result.inspect
      #
      # @return [ String ] The inspection.
      #
      # @since 2.0.0
      # @api public
      def inspect
        "#<#{self.class.name}:0x#{object_id} documents=#{documents}>"
      end

      # Get the reply from the result.
      #
      # Returns nil if there is no reply (i.e. the operation was an
      # unacknowledged write).
      #
      # @return [ Protocol::Message ] The first reply.
      #
      # @since 2.0.0
      # @api private
      def reply
        nil
      end

      # Get the number of documents returned by the server in this batch.
      #
      # @return [ Integer ] The number of documents returned.
      #
      # @since 2.0.0
      # @api public
      def returned_count
        0
      end

      # If the result was a command then determine if it was considered a
      # success.
      #
      # @note If the write was unacknowledged, then this will always return
      #   true.
      #
      # @example Was the command successful?
      #   result.successful?
      #
      # @return [ true, false ] If the command was successful.
      #
      # @since 2.0.0
      # @api public
      def successful?
        true
      end

      # Check the first document's ok field.
      #
      # @example Check the ok field.
      #   result.ok?
      #
      # @return [ true, false ] If the command returned ok.
      #
      # @since 2.1.0
      # @api public
      def ok?
        true
      end

      # Validate the result by checking for any errors.
      #
      # @note This only checks for errors with writes since authentication is
      #   handled at the connection level and any authentication errors would
      #   be raised there, before a Result is ever created.
      #
      # @example Validate the result.
      #   result.validate!
      #
      # @raise [ Error::OperationFailure ] If an error is in the result.
      #
      # @return [ Result ] The result if verification passed.
      #
      # @since 2.0.0
      # @api private
      def validate!
        self
      end

      # @return [ TopologyVersion | nil ] The topology version.
      #
      # @api private
      def topology_version
        nil
      end

      # Get the number of documents written by the server.
      #
      # @example Get the number of documents written.
      #   result.written_count
      #
      # @return [ Integer ] The number of documents written.
      #
      # @since 2.0.0
      # @api public
      def written_count
        0
      end

      # @api public
      alias :n :written_count

      # Get the operation time reported in the server response.
      #
      # @example Get the operation time.
      #   result.operation_time
      #
      # @return [ Object | nil ] The operation time value.
      #
      # @since 2.5.0
      # @api public
      def operation_time
        first_document && first_document[OPERATION_TIME]
      end

      # Get the cluster time reported in the server response.
      #
      # @example Get the cluster time.
      #   result.cluster_time
      #
      # @return [ ClusterTime | nil ] The cluster time document.
      #
      # Changed in version 2.9.0: This attribute became an instance of
      # ClusterTime, which is a subclass of BSON::Document.
      # Previously it was an instance of BSON::Document.
      #
      # @since 2.5.0
      # @api public
      def cluster_time
        first_document && ClusterTime[first_document['$clusterTime']]
      end

      # Gets the set of error labels associated with the result.
      #
      # @example Get the labels.
      #   result.labels
      #
      # @return [ Array ] labels The set of labels.
      #
      # @since 2.7.0
      # @api private
      def labels
        @labels ||= parser.labels
      end

      # Whether the operation failed with a write concern error.
      #
      # @api private
      def write_concern_error?
        !!(first_document && first_document['writeConcernError'])
      end

      def snapshot_timestamp
        nil
      end
    end
  end
end
