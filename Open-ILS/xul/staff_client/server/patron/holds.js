dump('entering patron.holds.js\n');

if (typeof patron == 'undefined') patron = {};
patron.holds = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

patron.holds.prototype = {

	'retrieve_ids' : [],

	'holds_map' : {},

	'init' : function( params ) {

		var obj = this;

		obj.patron_id = params['patron_id'];
		obj.docid = params['docid'];
		obj.shelf = params['shelf'];

		JSAN.use('circ.util');
		var columns = circ.util.hold_columns( 
			{ 
				'title' : { 'hidden' : false, 'flex' : '3' },
				'request_time' : { 'hidden' : false },
				'pickup_lib_shortname' : { 'hidden' : false },
				'hold_type' : { 'hidden' : true },
				'current_copy' : { 'hidden' : true },
				'capture_time' : { 'hidden' : true },
			} 
		);

		JSAN.use('util.list'); obj.list = new util.list('holds_list');
		obj.list.init(
			{
				'columns' : columns,
				'map_row_to_column' : circ.util.std_map_row_to_column(),
				'retrieve_row' : function(params) {
					var row = params.row;
					try {
						var status_robj = obj.network.simple_request('FM_AHR_STATUS',[ ses(), row.my.ahr.id() ]);
						row.my.status = status_robj;
						if (row.my.ahr.current_copy()) {
							row.my.acp = obj.network.simple_request( 'FM_ACP_RETRIEVE', [ row.my.ahr.current_copy() ]);
						}
						switch(row.my.ahr.hold_type()) {
							case 'M' :
								row.my.mvr = obj.network.request(
									api.MODS_SLIM_METARECORD_RETRIEVE.app,
									api.MODS_SLIM_METARECORD_RETRIEVE.method,
									[ row.my.ahr.target() ]
								);
							break;
							case 'T' :
								row.my.mvr = obj.network.request(
									api.MODS_SLIM_RECORD_RETRIEVE.app,
									api.MODS_SLIM_RECORD_RETRIEVE.method,
									[ row.my.ahr.target() ]
								);
							break;
							case 'V' :
								row.my.acn = obj.network.simple_request( 'FM_ACN_RETRIEVE', [ row.my.ahr.target() ]);
								row.my.mvr = obj.network.request(
									api.MODS_SLIM_RECORD_RETRIEVE.app,
									api.MODS_SLIM_RECORD_RETRIEVE.method,
									[ row.my.acn.record() ]
								);
							break;
							case 'C' :
								if (typeof row.my.acp == 'undefined') {
									row.my.acp = obj.network.simple_request( 'FM_ACP_RETRIEVE', [ row.my.ahr.target() ]);
								}
								if (typeof row.my.acp.call_number() == 'object') {
									row.my.acn = my.acp.call_number();
								} else {
									row.my.acn = obj.network.simple_request( 'FM_ACN_RETRIEVE', [ row.my.acp.call_number() ]);
								}
								row.my.mvr = obj.network.request(
									api.MODS_SLIM_RECORD_RETRIEVE.app,
									api.MODS_SLIM_RECORD_RETRIEVE.method,
									[ row.my.acn.record() ]
								);
							break;
						}
					} catch(E) {
						obj.error.sdump('D_ERROR','retrieve_row: ' + E );
					}
					if (typeof params.on_retrieve == 'function') {
						params.on_retrieve(row);
					}
					return row;
				},
				'on_select' : function(ev) {
					JSAN.use('util.functional');
					var sel = obj.list.retrieve_selection();
					obj.controller.view.sel_clip.setAttribute('disabled',sel.length < 1);
					obj.retrieve_ids = util.functional.map_list(
						sel,
						function(o) { return JSON2js( o.getAttribute('retrieve_id') ); }
					);
					if (obj.retrieve_ids.length > 0) {
						obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','false');
						obj.controller.view.sel_mark_items_missing.setAttribute('disabled','false');
						obj.controller.view.sel_copy_details.setAttribute('disabled','false');
						obj.controller.view.sel_patron.setAttribute('disabled','false');
						obj.controller.view.cmd_retrieve_patron.setAttribute('disabled','false');
						obj.controller.view.cmd_holds_edit_pickup_lib.setAttribute('disabled','false');
						obj.controller.view.cmd_holds_edit_phone_notify.setAttribute('disabled','false');
						obj.controller.view.cmd_holds_edit_email_notify.setAttribute('disabled','false');
						obj.controller.view.cmd_holds_edit_selection_depth.setAttribute('disabled','false');
						obj.controller.view.cmd_show_notifications.setAttribute('disabled','false');
						obj.controller.view.cmd_holds_retarget.setAttribute('disabled','false');
						obj.controller.view.cmd_holds_cancel.setAttribute('disabled','false');
						obj.controller.view.cmd_show_catalog.setAttribute('disabled','false');
					} else {
						obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','true');
						obj.controller.view.sel_mark_items_missing.setAttribute('disabled','true');
						obj.controller.view.sel_copy_details.setAttribute('disabled','true');
						obj.controller.view.sel_patron.setAttribute('disabled','true');
						obj.controller.view.cmd_retrieve_patron.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_edit_pickup_lib.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_edit_phone_notify.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_edit_email_notify.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_edit_selection_depth.setAttribute('disabled','true');
						obj.controller.view.cmd_show_notifications.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_retarget.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_cancel.setAttribute('disabled','true');
						obj.controller.view.cmd_show_catalog.setAttribute('disabled','true');
					}
				},

			}
		);
		
		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				'control_map' : {
					'save_columns' : [ [ 'command' ], function() { obj.list.save_columns(); } ],
					'sel_clip' : [
						['command'],
						function() { obj.list.clipboard(); }
					],
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'sel_patron' : [
						['command'],
						function() {
							JSAN.use('circ.util');
							circ.util.show_last_few_circs(obj.retrieve_ids);
						}
					],
					'sel_mark_items_damaged' : [
						['command'],
						function() {
							JSAN.use('cat.util'); JSAN.use('util.functional');
							cat.util.mark_item_damaged( util.functional.map_list( obj.retrieve_ids, function(o) { return o.copy_id; } ) );
						}
					],
					'sel_mark_items_missing' : [
						['command'],
						function() {
							JSAN.use('cat.util'); JSAN.use('util.functional');
							cat.util.mark_item_missing( util.functional.map_list( obj.retrieve_ids, function(o) { return o.copy_id; } ) );
						}
					],
					'sel_copy_details' : [
						['command'],
						function() {
							JSAN.use('circ.util');
							for (var i = 0; i < obj.retrieve_ids.length; i++) {
								if (obj.retrieve_ids[i].copy_id) circ.util.show_copy_details( obj.retrieve_ids[i].copy_id );
							}
						}
					],
					'cmd_holds_print' : [
						['command'],
						function() {
							try {
								dump(js2JSON(obj.list.dump_with_keys()) + '\n');
								function flesh_callback() {
									try {
										JSAN.use('patron.util');
										var params = { 
											'patron' : patron.util.retrieve_au_via_id(ses(),obj.patron_id), 
											'lib' : obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ],
											'staff' : obj.data.list.au[0],
											'header' : obj.data.print_list_templates.holds.header,
											'line_item' : obj.data.print_list_templates.holds.line_item,
											'footer' : obj.data.print_list_templates.holds.footer,
											'type' : obj.data.print_list_templates.holds.type,
											'list' : obj.list.dump_with_keys(),
										};
										JSAN.use('util.print'); var print = new util.print();
										print.tree_list( params );
										setTimeout(function(){obj.list.on_all_fleshed = null;},0);
									} catch(E) {
										obj.error.standard_unexpected_error_alert('print 2',E);
									}
								}
								obj.list.on_all_fleshed = flesh_callback;
								obj.list.full_retrieve();
							} catch(E) {
								obj.error.standard_unexpected_error_alert('print 1',E);
							}
						}
					],
					'cmd_show_notifications' : [
						['command'],
						function() {
							try {
								JSAN.use('util.window'); var win = new util.window();
								for (var i = 0; i < obj.retrieve_ids.length; i++) {
									netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
									win.open(
										xulG.url_prefix(urls.XUL_HOLD_NOTICES) 
										+ '?ahr_id=' + obj.retrieve_ids[i].id,
										'hold_notices_' + obj.retrieve_ids[i].id,
										'chrome,resizable'
									);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Error rendering/retrieving hold notifications.',E);
							}
						}
					],
					'cmd_holds_edit_selection_depth' : [
						['command'],
						function() {
							try {
								JSAN.use('util.widgets'); JSAN.use('util.functional'); 
								var ws_type = obj.data.hash.aout[ obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ].ou_type() ];
								var list = util.functional.map_list(
									util.functional.filter_list(	
										obj.data.list.aout,
										function(o) {
											if (o.depth() > ws_type.depth()) return false;
											if (o.depth() < ws_type.depth()) return true;
											return (o.id() == ws_type.id());
										}
									),
									function(o) { 
										return [
											o.opac_label(),
											o.id(),
											false,
											( o.depth() * 2),
										]; 
									}
								);
								ml = util.widgets.make_menulist( list, obj.data.list.au[0].ws_ou() );
								ml.setAttribute('id','selection');
								ml.setAttribute('name','fancy_data');
								var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								xml += '<description>Please choose a Hold Range:</description>';
								xml += util.widgets.serialize_node(ml);
								xml += '</vbox>';
								var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								bot_xml += '<spacer flex="1"/><button label="Done" accesskey="D" name="fancy_submit"/>';
								bot_xml += '<button label="Cancel" accesskey="C" name="fancy_cancel"/></hbox>';
								netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
								obj.data.temp_mid = xml; obj.data.stash('temp_mid');
								obj.data.temp_bot = bot_xml; obj.data.stash('temp_bot');
								window.open(
									urls.XUL_FANCY_PROMPT
									+ '?xml_in_stash=temp_mid'
									+ '&bottom_xml_in_stash=temp_bot'
									+ '&title=' + window.escape('Choose a Pick Up Library'),
									'fancy_prompt', 'chrome,resizable,modal'
								);
								obj.data.init({'via':'stash'});
								if (obj.data.fancy_prompt_data == '') { return; }
								var selection = obj.data.fancy_prompt_data.selection;
								var msg = 'Are you sure you would like to change the Hold Range for hold' + ( obj.retrieve_ids.length > 1 ? 's ' : ' ') + util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ') + ' to "' + obj.data.hash.aout[selection].opac_label() + '"?';
								var r = obj.error.yns_alert(msg,'Modifying Holds','Yes','No',null,'Check here to confirm this message');
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
										hold.selection_depth( obj.data.hash.aout[selection].depth() ); hold.ischanged('1');
										var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.retrieve();
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Holds not likely modified.',E);
							}
						}
					],

					'cmd_holds_edit_pickup_lib' : [
						['command'],
						function() {
							try {
								JSAN.use('util.widgets'); JSAN.use('util.functional'); 
								var list = util.functional.map_list(
									obj.data.list.aou,
									function(o) { 
										var sname = o.shortname(); for (i = sname.length; i < 20; i++) sname += ' ';
										return [
											o.name() ? sname + ' ' + o.name() : o.shortname(),
											o.id(),
											( obj.data.hash.aout[ o.ou_type() ].can_have_users() == 0),
											( obj.data.hash.aout[ o.ou_type() ].depth() * 2),
										]; 
									}
								);
								ml = util.widgets.make_menulist( list, obj.data.list.au[0].ws_ou() );
								ml.setAttribute('id','lib');
								ml.setAttribute('name','fancy_data');
								var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								xml += '<description>Please choose a new Pickup Library:</description>';
								xml += util.widgets.serialize_node(ml);
								xml += '</vbox>';
								var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								bot_xml += '<spacer flex="1"/><button label="Done" accesskey="D" name="fancy_submit"/>';
								bot_xml += '<button label="Cancel" accesskey="C" name="fancy_cancel"/></hbox>';
								netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
								obj.data.temp_mid = xml; obj.data.stash('temp_mid');
								obj.data.temp_bot = bot_xml; obj.data.stash('temp_bot');
								window.open(
									urls.XUL_FANCY_PROMPT
									+ '?xml_in_stash=temp_mid'
									+ '&bottom_xml_in_stash=temp_bot'
									+ '&title=' + window.escape('Choose a Pick Up Library'),
									'fancy_prompt', 'chrome,resizable,modal'
								);
								obj.data.init({'via':'stash'});
								if (obj.data.fancy_prompt_data == '') { return; }
								var pickup_lib = obj.data.fancy_prompt_data.lib;
								var msg = 'Are you sure you would like to change the Pick Up Lib for hold' + ( obj.retrieve_ids.length > 1 ? 's ' : ' ') + util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ') + ' to ' + obj.data.hash.aou[pickup_lib].shortname() + '?';
								var r = obj.error.yns_alert(msg,'Modifying Holds','Yes','No',null,'Check here to confirm this message');
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
										hold.pickup_lib(  pickup_lib ); hold.ischanged('1');
										var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.retrieve();
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Holds not likely modified.',E);
							}
						}
					],
					'cmd_holds_edit_phone_notify' : [
						['command'],
						function() {
							try {
								var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								xml += '<description>Please enter a new phone number for hold notification (leave the field empty to disable phone notification):</description>';
								xml += '<textbox id="phone" name="fancy_data"/>';
								xml += '</vbox>';
								var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								bot_xml += '<spacer flex="1"/><button label="Done" accesskey="D" name="fancy_submit"/>';
								bot_xml += '<button label="Cancel" accesskey="C" name="fancy_cancel"/></hbox>';
								netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
								obj.data.temp_mid = xml; obj.data.stash('temp_mid');
								obj.data.temp_bot = bot_xml; obj.data.stash('temp_bot');
								window.open(
									urls.XUL_FANCY_PROMPT
									+ '?xml_in_stash=temp_mid'
									+ '&bottom_xml_in_stash=temp_bot'
									+ '&title=' + window.escape('Choose a Hold Notification Phone Number')
									+ '&focus=phone',
									'fancy_prompt', 'chrome,resizable,modal'
								);
								obj.data.init({'via':'stash'});
								if (obj.data.fancy_prompt_data == '') { return; }
								var phone = obj.data.fancy_prompt_data.phone;
								var msg = 'Are you sure you would like to change the Notification Phone Number for hold' + ( obj.retrieve_ids.length > 1 ? 's ' : ' ') + util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ') + ' to "' + phone + '"?';
								var r = obj.error.yns_alert(msg,'Modifying Holds','Yes','No',null,'Check here to confirm this message');
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
										hold.phone_notify(  phone ); hold.ischanged('1');
										var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.retrieve();
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Holds not likely modified.',E);
							}
						}
					],
					'cmd_holds_edit_email_notify' : [
						['command'],
						function() {
							try {
								var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								xml += '<description>Send email notifications (when appropriate)?  The email address used is found in the hold recepient account.</description>';
								xml += '<hbox><button value="email" label="Email" accesskey="E" name="fancy_submit"/>';
								xml += '<button value="noemail" label="No Email" accesskey="N" name="fancy_submit"/></hbox>';
								xml += '</vbox>';
								var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								bot_xml += '<spacer flex="1"/><button label="Cancel" accesskey="C" name="fancy_cancel"/></hbox>';
								netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
								obj.data.temp_mid = xml; obj.data.stash('temp_mid');
								obj.data.temp_bot = bot_xml; obj.data.stash('temp_bot');
								window.open(
									urls.XUL_FANCY_PROMPT
									+ '?xml_in_stash=temp_mid'
									+ '&bottom_xml_in_stash=temp_bot'
									+ '&title=' + window.escape('Set Email Notification for Holds'),
									'fancy_prompt', 'chrome,resizable,modal'
								);
								obj.data.init({'via':'stash'});
								if (obj.data.fancy_prompt_data == '') { return; }
								var email = obj.data.fancy_prompt_data.fancy_submit == 'email' ? get_db_true() : get_db_false();
								var msg = 'Are you sure you would like ' + ( get_bool( email ) ? 'enable' : 'disable' ) + ' email notification for hold' + ( obj.retrieve_ids.length > 1 ? 's ' : ' ') + util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ') + '?';
								var r = obj.error.yns_alert(msg,'Modifying Holds','Yes','No',null,'Check here to confirm this message');
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
										hold.email_notify(  email ); hold.ischanged('1');
										var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.retrieve();
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Holds not likely modified.',E);
							}
						}
					],


					'cmd_holds_retarget' : [
						['command'],
						function() {
							try {
								JSAN.use('util.functional');
								var msg = 'Are you sure you would like to reset hold' + ( obj.retrieve_ids.length > 1 ? 's ' : ' ') + util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ') + '?';
								var r = obj.error.yns_alert(msg,'Resetting Holds','Yes','No',null,'Check here to confirm this message');
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var robj = obj.network.simple_request('FM_AHR_RESET',[ ses(), obj.retrieve_ids[i].id]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.retrieve();
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Holds not likely reset.',E);
							}

						}
					],

					'cmd_holds_cancel' : [
						['command'],
						function() {
							try {
								JSAN.use('util.functional');
								var msg = 'Are you sure you would like to cancel hold' + ( obj.retrieve_ids.length > 1 ? 's ' : ' ') + util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ') + '?';
								var r = obj.error.yns_alert(msg,'Cancelling Holds','Yes','No',null,'Check here to confirm this message');
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var robj = obj.network.simple_request('FM_AHR_CANCEL',[ ses(), obj.retrieve_ids[i].id]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.retrieve();
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Holds not likely cancelled.',E);
							}
						}
					],
					'cmd_retrieve_patron' : [
						['command'],
						function() {
							try {
								var seen = {};
								for (var i = 0; i < obj.retrieve_ids.length; i++) {
									var patron_id = obj.retrieve_ids[i].usr;
									if (seen[patron_id]) continue; seen[patron_id] = true;
									xulG.new_tab(
										xulG.url_prefix(urls.XUL_PATRON_DISPLAY) + '?id=' + patron_id, 
										{}, 
										{}
									);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('',E);
							}
						}
					],
					'cmd_show_catalog' : [
						['command'],
						function() {
							try {
								for (var i = 0; i < obj.retrieve_ids.length; i++) {
									var htarget = obj.retrieve_ids[i].target;
									var htype = obj.retrieve_ids[i].type;
									var opac_url;
									switch(htype) {
										case 'M' :
											opac_url = xulG.url_prefix( urls.opac_rresult ) + '?m=' + htarget;
										break;
										case 'T' : 
											opac_url = xulG.url_prefix( urls.opac_rdetail ) + '?r=' + htarget;
										break;
										case 'V' :
											var my_acn = obj.network.simple_request( 'FM_ACN_RETRIEVE', [ htarget ]);
											opac_url = xulG.url_prefix( urls.opac_rdetail) + '?r=' + my_acn.record();
										break;
										case 'C' :
											var my_acp = obj.network.simple_request( 'FM_ACP_RETRIEVE', [ htarget ]);
											var my_acn;
											if (typeof my_acp.call_number() == 'object') {
												my_acn = my.acp.call_number();
											} else {
												my_acn = obj.network.simple_request( 'FM_ACN_RETRIEVE', 
													[ my_acp.call_number() ]);
											}
											opac_url = xulG.url_prefix( urls.opac_rdetail) + '?r=' + my_acn.record();
										break;
										default:
											obj.error.standard_unexpected_error_alert("I don't understand the hold type of " + htype + ", so I can't jump to the appropriate record in the catalog.", obj.retrieve_ids[i]);
											continue;
										break;
									}
									var content_params = { 
										'session' : ses(),
										'authtime' : ses('authtime'),
										'opac_url' : opac_url,
									};
									xulG.new_tab(
										xulG.url_prefix(urls.XUL_OPAC_WRAPPER), 
										{'tab_name': htype == 'M' ? 'Catalog' : 'Retrieving title...'}, 
										content_params
									);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('',E);
							}
						}
					],
				}
			}
		);
		obj.controller.render();

		obj.retrieve();

		obj.controller.view.cmd_retrieve_patron.setAttribute('disabled','true');
		obj.controller.view.cmd_holds_edit_pickup_lib.setAttribute('disabled','true');
		obj.controller.view.cmd_holds_edit_phone_notify.setAttribute('disabled','true');
		obj.controller.view.cmd_holds_edit_email_notify.setAttribute('disabled','true');
		obj.controller.view.cmd_holds_edit_selection_depth.setAttribute('disabled','true');
		obj.controller.view.cmd_show_notifications.setAttribute('disabled','true');
		obj.controller.view.cmd_holds_retarget.setAttribute('disabled','true');
		obj.controller.view.cmd_holds_cancel.setAttribute('disabled','true');
		obj.controller.view.cmd_show_catalog.setAttribute('disabled','true');
	},

	'retrieve' : function(dont_show_me_the_list_change) {
		var obj = this;
		if (window.xulG && window.xulG.holds) {
			obj.holds = window.xulG.holds;
		} else {
			var method; var param1; var param2 = undefined;
			if (obj.patron_id) {
				method = 'FM_AHR_RETRIEVE_VIA_AU'; 
				param1 = obj.patron_id; 
				obj.controller.view.cmd_retrieve_patron.setAttribute('hidden','true');
			} else if (obj.docid) {
				method = 'FM_AHR_RETRIEVE_VIA_BRE'; 
				param1 = obj.docid; 
				obj.controller.view.cmd_retrieve_patron.setAttribute('hidden','false');
			} else if (obj.pull) {
				method = 'FM_AHR_PULL_LIST'; 
				param1 = 50; param2 = 0;
			} else if (obj.shelf) {
				method = 'FM_AHR_ONSHELF_RETRIEVE'; 
				param1 = obj.data.list.au[0].ws_ou(); 
				obj.controller.view.cmd_retrieve_patron.setAttribute('hidden','false');
			} else {
				//method = 'FM_AHR_RETRIEVE_VIA_PICKUP_AOU'; 
				method = 'FM_AHR_PULL_LIST'; 
				param1 = 50; param2 = 0;
				obj.controller.view.cmd_retrieve_patron.setAttribute('hidden','false');
			}
			obj.holds = obj.network.simple_request( method, [ ses(), param1, param2 ]);
		}

		function gen_list_append(hold) {
			return function() {
				obj.holds_map[ hold.id() ] = hold;
				obj.list.append(
					{
						'retrieve_id' : js2JSON({'copy_id':hold.current_copy(),'id':hold.id(),'type':hold.hold_type(),'target':hold.target(),'usr':hold.usr(),}),
						'row' : {
							'my' : {
								'ahr' : hold,
							}
						}
					}
				);
			};
		}

		obj.list.clear();

		JSAN.use('util.exec'); var exec = new util.exec(2);
		var rows = [];
		for (var i in obj.holds) {
			rows.push( gen_list_append(obj.holds[i]) );
		}
		exec.chain( rows );
	
		if (!dont_show_me_the_list_change) {
			if (window.xulG && typeof window.xulG.on_list_change == 'function') {
				try { window.xulG.on_list_change(obj.holds); } catch(E) { this.error.sdump('D_ERROR',E); }
			}
		}
	},
}

dump('exiting patron.holds.js\n');
