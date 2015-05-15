module.exports =
	find:		(req, res) ->
		[fulfill, reject] = ModelService.handler(res)
		ModelService.Roster.find(req, res).then fulfill, reject
	
	findOne:	ModelService.notImplemented
	
	create:		(req, res) ->
		[fulfill, reject] = ModelService.handler(res)
		ModelService.Roster.create(req, res).then fulfill, reject
	
	update:		(req, res) ->
		[fulfill, reject] = ModelService.handler(res)
		ModelService.Roster.update(req, res).then fulfill, reject
	
	destroy:	(req, res) ->
		[fulfill, reject] = ModelService.handler(res)
		ModelService.Roster.destroy(req, res).then fulfill, reject
	
	populate:	ModelService.notImplemented
	
	add:		ModelService.notImplemented
	
	remove:		ModelService.notImplemented