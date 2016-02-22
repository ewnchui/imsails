env = require '../../env.coffee'
req = require 'supertest'		
path = require 'path'
util = require 'util'
_ = require 'lodash'
require 'shelljs/global'
fs = require 'fs'
Promise = require 'promise'

describe 'MsgController', ->
	@timeout env.timeout
	
	tokens = null
	users = null
	group = null
	msgs = []
	
	before (done) ->
		env.getTokens()
			.then (res) ->
				tokens = res
				env.getUsers()
					.then (res) ->
						users = res
						env.getGroup()
							.then (res) ->
								group = res
								done()
			.catch done
						
	describe 'create', ->
		it "text msg to #{env.users[0].jid}", (done) ->
			req sails.hooks.http.app
				.post '/api/msg'
				.set 'Authorization', "Bearer #{tokens[1]}"
				.send
					to: 		env.users[0].jid
					body:		"msg from #{env.users[1].id} to #{env.users[0].id}"
				.expect 201
				.expect (res) ->
					msgs[0] = res.body
				.expect ->
					Promise
						.all [
							sails.models.user.findOne username: env.users[0].id
							sails.models.user.findOne username: env.users[1].id
						]
						.then (users) ->
							Promise
								.all [
									sails.models.roster.findOne jid: users[0].jid, createdBy: users[1].id
									sails.models.roster.findOne jid: users[1].jid, createdBy: users[0].id
								]
								.then (rosters) ->
									# check if both roster exists
									if not (rosters[0] and rosters[1])
										throw "rosters #{users[0].jid} or #{users[1].jid} not properly created"
						.catch (err) ->
							throw err
				.end done
		
		it 'image attachement', (done) ->
			req sails.hooks.http.app
				.post '/api/msg/file'
				.set 'Authorization', "Bearer #{tokens[1]}"
				.field 'to', users[0].jid
				.attach 'file', 'test/data/test.png'
				.expect (res) ->
					msgs[1] = res.body
				.expect 201
				.end done
		
		it 'audio attachement', (done) ->
			req sails.hooks.http.app
				.post '/api/msg/file'
				.set 'Authorization', "Bearer #{tokens[1]}"
				.field 'to', users[0].jid
				.attach 'file', 'test/data/test.mp3'
				.expect (res) ->
					msgs[2] = res.body
				.expect 201
				.end done
				
	describe 'read', ->
		fs = require 'fs'
		qs = require 'querystring'
		
		it "list msgs sent", (done) ->
			param = qs.stringify 
				to: 	users[0].jid
				type:	'chat'
			req sails.hooks.http.app
				.get "/api/msg?#{param}"
				.set 'Authorization', "Bearer #{tokens[1]}"
				.expect 200
				.end done
		
		it "thumbnail of the image file", (done) ->
			req sails.hooks.http.app
				.get "/api/msg/file/thumb/#{msgs[1].id}"
				.set 'Authorization', "Bearer #{tokens[1]}"
				.expect 200
				.parse (res, cb) ->
					res.pipe fs.createWriteStream '/tmp/test.thumb.png'
						.on 'finish', cb
						.on 'error', cb
				.end done
				
		it "image file sent", (done) ->
			req sails.hooks.http.app
				.get "/api/msg/file/#{msgs[1].id}"
				.set 'Authorization', "Bearer #{tokens[1]}"
				.expect 200
				.parse (res, cb) ->
					res.pipe fs.createWriteStream '/tmp/test.png'
						.on 'finish', ->
							ret = exec "diff /tmp/test.png test/data/test.png"
							if ret.code != 0
								throw new Error 'file mismatch'
							cb()
						.on 'error', cb
				.end done
					
		it "audio file sent", (done) ->
			req sails.hooks.http.app
				.get "/api/msg/file/#{msgs[2].id}"
				.set 'Authorization', "Bearer #{tokens[1]}"
				.expect 200
				.parse (res, cb) ->
					res.pipe fs.createWriteStream '/tmp/test.mp3'
						.on 'finish', ->
							ret = exec "diff /tmp/test.mp3 test/data/test.mp3"
							if ret.code != 0
								throw new Error 'file mismatch'
							cb()
						.on 'error', cb
				.end done