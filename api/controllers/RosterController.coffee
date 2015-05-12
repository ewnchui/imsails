actionUtil = require 'sails/lib/hooks/blueprints/actionUtil'
_ = require 'underscore'
Promise = require 'promise'

module.exports =
	find: (req, res) ->
		Model = actionUtil.parseModel(req)
	
		if actionUtil.parsePk(req)
			return require('sails/lib/hooks/blueprints/actions/findOne')(req,res)
	
		count = new Promise (fulfill, reject) ->
			Model.count()
				.where( actionUtil.parseCriteria(req) )
				.exec (err, data) ->
					if err?
						reject err
					fulfill data
		query = new Promise (fulfill, reject) ->
			Model.find()
				.where( actionUtil.parseCriteria(req) )
				.limit( actionUtil.parseLimit(req) )
				.skip( actionUtil.parseSkip(req) )
				.sort( actionUtil.parseSort(req) )
				.exec (err, data) ->
					if err?
						reject err
					fulfill data
		Promise.all([count, query])
			.then (data) ->
				ret =
					count:		data[0]
					results:	data[1]
				p = Promise.all _.map ret.results, (roster) ->
					XmppService.VCard.read req.user, roster.jid
				p
					.then (vcards) ->
						_.each ret.results, (item, index) ->
							item.photo = vcards[index].photo
						if req._sails.hooks.pubsub && req.isSocket
							Model.subscribe(req, ret)
						if req.options.autoWatch
							Model.watch(req)
						_.each ret.results, (record) ->
							actionUtil.subscribeDeep(req, record)
						res.ok ret
			.catch res.serverError