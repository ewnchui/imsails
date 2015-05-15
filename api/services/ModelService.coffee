actionUtil = require 'sails/lib/hooks/blueprints/actionUtil'
_ = require 'lodash'
XMPP = require 'stanza.io'
Promise = require 'promise'

handler = (res) ->
	fulfill = (ret) ->
		res.json ret
	reject = (err) ->
		res.serverError JSON.stringify(err, ["message", "arguments", "type", "name"])
	[fulfill, reject]
	
notImplemented = (req, res) ->
	res.serverError 'not implemeneted'
	
actionUtil = _.extend actionUtil,
	_parseModel:	actionUtil.parseModel
	
	_parseValues:	actionUtil.parseValues
	
	_parseCriteria:	actionUtil.parseCriteria
	
	parseModel: (req) ->
		model = req.options.model || req.options.controller
		if !model
			throw new Error(util.format('No "model" specified in route options.'))
			
		Model = MongoService.models[model]
		if !Model
			throw new Error(util.format('Invalid route option, "model".\nI don\'t know about any models named: `%s`',model))
		
		return Model
		
	parseValues: (req) ->
		_.omit @_parseValues(req), 'id', '_id', '__v', 'createdBy', 'createdAt', 'dateCreated', 'updatedBy', 'updatedAt', 'lastUpdated'	

	# replace id: value criteria with _id: value
	parseCriteria: (req) ->
		ret = @_parseCriteria(req)
		if ret.id
			ret._id = ret.id
		_.omit ret, 'id' 
		
Model =
	# change to blueprint create action
	#   model.createdBy = req.user
	create:	(req, res, model = actionUtil.parseModel(req)) ->
		new Promise (fulfill, reject) ->
			values = _.extend actionUtil.parseValues(req), createdBy: req.user
			model.create values, (err, newInstance) ->
				if err
					reject err
				else
					fulfill newInstance
			
	# change to blueprint find action
	#   return { count: count of models, results: array of models filtered with the input criteria and condition } instead of models only 
	find: (req, res, cond = {}, model = actionUtil.parseModel(req)) ->
		new Promise (fulfill, reject) ->
			count = new Promise (fulfill, reject) ->
				model.count()
					.where( actionUtil.parseCriteria(req) )
					.exec (err, data) ->
						if err
							reject err
						else
							fulfill data
			query = new Promise (fulfill, reject) ->
				model.find()
					.where( actionUtil.parseCriteria(req) )
					.limit( actionUtil.parseLimit(req) )
					.skip( actionUtil.parseSkip(req) )
					.sort( actionUtil.parseSort(req) )
					.exec (err, data) ->
						if err
							reject err
						else
							fulfill data
			Promise.all([count, query])
				.then (data) ->
					fulfill
						count:		data[0]
						results:	data[1]
				.catch reject
				
	# change to blueprint update action
	#   model.updatedBy = req.user
	#	filtered by input.id == model.id and input.__v == model.__v
	update: (req, res, cond = {}, model = actionUtil.parseModel(req)) ->
		new Promise (fulfill, reject) ->
			values = _.extend actionUtil.parseValues(req), updatedBy: req.user
			cond = actionUtil.parseCriteria(req)
			
			model.findOneAndUpdate cond, values, (err, matchingRecord) ->
				if err
					reject err
				else
					fulfill matchingRecord
	
	destroy: (req, res, cond = {}, model = actionUtil.parseModel(req)) ->
		new Promise (fulfill, reject) ->
			model.findOneAndRemove actionUtil.parseCriteria(req), (err, data) ->
				if err
					reject err
				else
					if data
						fulfill 'successfully deleted'
					else
						reject 'not found'
		
Bookmark =

	list: (user) ->
		return new Promise (fulfill, reject) ->
			user.xmpp.getBookmarks (err, res) ->
				if err
					reject err 
				else
					fulfill if 'conferences' of res.privateStorage.bookmarks then res.privateStorage.bookmarks.conferences else []
					
	create: (user, data) ->
		# join the room
		user.xmpp.joinRoom data.jid, user.xmpp.jid.local
		return user.xmpp.addBookmark(data)
		
	del: (user, jid) ->
		return new Promise (fulfill, reject) ->
			user.xmpp.removeBookmark jid, (err, res) ->
				if err
					reject err 
				else
					fulfill 'deleted successfully'

Room = 

	list: (user) ->
		return new Promise (fulfill, reject) ->
			user.xmpp.getDiscoItems sails.config.xmpp.muc, '', (err, res) ->
				if err
					reject err
				else
					results = if 'items' of res.discoItems then res.discoItems.items else []
					fulfill
						count: 		results.length
						results:	results					
					
	create: (user, jid, privateroom) ->
		return new Promise (fulfill, reject) ->
			# join the room to create transient room
			user.xmpp.joinRoom jid, user.xmpp.jid.local
			
			success = (config) ->
				data =
					name: 		(new user.xmpp.JID jid).local
					autoJoin:	true
					jid:		jid
				p1 = Bookmark.create user, data
					
				_.findWhere(config.fields, name: 'muc#roomconfig_persistentroom')?.value = true
				if privateroom
					_.findWhere(config.fields, name: 'muc#roomconfig_membersonly')?.value = true
				config.type = 'submit'
				p2 = Room.update(user, jid, config)
				
				p = Promise.all([p1, p2]).then fulfill, reject 
			
			# read config
			Room.read(user, jid).then success, reject
			
	read: (user, jid) ->
		return new Promise (fulfill, reject) ->
			user.xmpp.getRoomConfig jid, (err, res) ->
				if err
					reject err
				else
					fulfill res.mucOwner.form
	
	update: (user, jid, data) ->
		return new Promise (fulfill, reject) ->
			user.xmpp.configureRoom jid, data, (err, res) ->
				if err
					reject err
				else
					fulfill res

	del: (user, jid) ->
		return new Promise (fulfill, reject) ->
			success = (config) ->
				_.findWhere(config.fields, name: 'muc#roomconfig_persistentroom')?.value = false
				config.type = 'submit'
				Room.update(user, jid, config).then fulfill, reject
			
			# read config
			Room.read(user, jid).then success, reject

User =
	find: (req, res) ->
		Model.find req, res, {}, MongoService.models.user

Vcard =
	find: (req, res) ->
		new Promise (fulfill, reject) ->
			User.find req, res
				.then (ret) ->
					p = Promise.all _.map ret.results, (item) ->
						XmppService.Vcard.findOne req.user, "#{item.username}@#{sails.config.xmpp.domain}"
					p
						.then (vcards) ->
							ret.results = vcards
							fulfill ret
						.catch reject
				.catch reject
		
	update: (req, res) ->
		data = actionUtil.parseValues req
		XmppService.update req.user, data
	
Roster =

	find: (req, res) ->
		new Promise (fulfill, reject) ->
			Model.find(req, res, createdBy: req.user)
				.then (ret) ->
					p = Promise.all _.map ret.results, (roster) ->
						XmppService.Vcard.findOne req.user, roster.jid
					p
						.then (vcards) ->
							ret.results = _.map ret.results, (item, index) ->
								_.extend item.toJSON(), photo: vcards[index].photo
							fulfill ret
						.catch reject
				.catch reject 
	
	create: (req, res) ->
		Model.create(req, res)
		
	update: (req, res) ->
		Model.update(req, res, createdBy: req.user)
					
	destroy: (req, res) ->
		Model.destroy(req, res)
		 
module.exports = 
	handler:		handler
	notImplemented:	notImplemented
	actionUtil:		actionUtil
	User:			User
	Vcard:			Vcard
	Roster:			Roster
	Bookmark:		Bookmark
	Room:			Room