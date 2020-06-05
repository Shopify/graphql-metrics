# frozen_string_literal: true

class CommentLoader < GraphQL::Batch::Loader
  def initialize(model)
    @model = model
  end

  def perform(ids)
    sleep 1

    ids.flatten.each do |id|
      fulfill(id, { id: id, body: 'Great blog!' })
    end
  end
end

class Comment < GraphQL::Schema::Object
  implements GraphQL::Types::Relay::Node
  description "A blog comment"

  field :id, ID, null: false
  field :body, String, null: false

  field :comments, [Comment], null: true do
    argument :ids, [ID], required: false
    argument :tags, [String], required: false
  end

  def comments(args)
    CommentLoader.for(Comment).load_many(args[:ids]).then { |comments| comments }
  end
end

class Post < GraphQL::Schema::Object
  implements GraphQL::Types::Relay::Node
  description "A blog post"

  field :id, ID, null: false

  field :title, String, null: false do
    argument :upcase, Boolean, required: false, prepare: ->(value, ctx) do
      if ctx[:raise_in_prepare]
        raise GraphQL::ExecutionError, "error in prepare"
      else
        value
      end
    end
  end

  field :body, String, null: false do
    argument :truncate, Boolean, required: false, default_value: false
  end

  field :deprecated_body, String, null: false, method: :body, deprecation_reason: 'Use `body` instead.'

  field :comments, [Comment], null: true do
    argument :ids, [ID], required: false
    argument :tags, [String], required: false
  end

  def comments(args)
    CommentLoader.for(Comment).load_many(args[:ids]).then { |comments| comments }
  end
end

class TagInput < GraphQL::Schema::InputObject
  argument :handle, String, "Unique handle of the tag", required: true
  argument :display_name, String, "Display name of the tag", required: true
end

class PostInput < GraphQL::Schema::InputObject
  argument :title, String, "Title for the post", required: true
  argument :body, String, "Body of the post", required: true
  argument :embedded_tags, [TagInput], "Embedded tags on a post", required: true
end

class PostUpdateInput < GraphQL::Schema::InputObject
  argument :title, String, "Title for the post", required: false, default_value: ""
  argument :body, String, "Body of the post", required: false
end

class PostUpvoteInput < GraphQL::Schema::InputObject
  argument :upvote_value, Integer, "Upvote 1 or -1", required: false
end

class PostCreate < GraphQL::Schema::Mutation
  argument :post, PostInput, required: true

  field :post, Post, null: false

  def resolve(post:)
    sleep 1
    { post: { id: 42, title: post.title, body: post.body } }
  end
end

class PostUpdate < GraphQL::Schema::Mutation
  argument :post, PostUpdateInput, required: true

  field :success, Boolean, null: false

  def resolve(post:)
    { success: true }
  end
end

class PostUpvote < GraphQL::Schema::Mutation
  argument :upvote, PostUpvoteInput, required: true

  field :success, Boolean, null: false

  def resolve(upvote:)
    { success: true }
  end
end

class MutationRoot < GraphQL::Schema::Object
  field :post_create, mutation: PostCreate
  field :post_update, mutation: PostUpdate
  field :post_upvote, mutation: PostUpvote
end

class QueryRoot < GraphQL::Schema::Object
  add_field(GraphQL::Types::Relay::NodeField)
  add_field(GraphQL::Types::Relay::NodesField)

  field :post, Post, null: true do
    argument :id, ID, required: true
    argument :locale, String, required: false, default_value: 'en-us'
  end

  def post(id:, locale:)
    return if id == 'missing_post'

    { id: 1, title: "Hello, world!", body: "... you're still here?" }
  end
end
