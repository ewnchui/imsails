env = require '../../env.coffee'
req = require 'supertest'		
path = require 'path'
util = require 'util'
_ = require 'lodash'
require 'shelljs/global'
fs = require 'fs'
Promise = require 'promise'

describe 'UserController', ->
	@timeout env.timeout
	
	tokens = null
	
	before (done) ->
		env.getTokens()
			.then (res) ->
				tokens = res
				done()
			.catch done
		
	describe 'create', ->
		_.each env.users, (user, index) ->
			it "user #{user.id}", (done) ->
				req sails.hooks.http.app
					.get '/api/user'
					.set 'Authorization', "Bearer #{tokens[index]}"
					.expect 200
					.end ->
						sails.models.user.findOne username: user.id
							.then (model) ->
								if _.isUndefined model
									throw new Error "user #{user.id} not properly created"
								done()
							.catch done