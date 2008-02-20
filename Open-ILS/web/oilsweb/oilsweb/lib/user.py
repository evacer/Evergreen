import osrf.ses, oils.utils.csedit, pylons.config, oils.utils.utils, oils.event, oils.const
from gettext import gettext as _

class AuthException(Exception):
    def __init__(self, info=''):
        self.info = info
    def __str__(self):
        return "%s: %s" % (self.__class__.__name__, unicode(self.info))

class User(object):
    ''' General purpose user utility methods '''

    def __init__(self, ctx):
        self.ctx = ctx

    def try_auto_login(self):
        if pylons.config.get('oils_demo_user'):
            evt = oils.utils.utils.login(
                pylons.config['oils_demo_user'],
                pylons.config['oils_demo_password'],
                'staff',
                pylons.config['oils_demo_workstation'])
            oils.event.Event.parse_and_raise(evt)
            self.ctx.authtoken.value = evt['payload']['authtoken']

    def fetch_user(self):
        ''' Grab the logged in user and their workstation '''

        if not self.ctx.authtoken.value:
            self.try_auto_login()

        if not self.ctx.authtoken.value:
            raise AuthException(_('No authentication token provided'))

        self.ctx.user.value = osrf.ses.ClientSession.atomic_request(
            'open-ils.auth', 
            'open-ils.auth.session.retrieve', self.ctx.authtoken.value)

        evt = oils.event.Event.parse_event(self.ctx.user.value)
        if evt and evt.text_code == 'NO_SESSION':
            # our authtoken has timed out.  See if we can autologin
            self.try_auto_login()
            if not self.ctx.authtoken.value:
                raise AuthException(_('No authentication token provided'))
            self.ctx.user.value = osrf.ses.ClientSession.atomic_request(
                'open-ils.auth', 
                'open-ils.auth.session.retrieve', self.ctx.authtoken.value)
            oils.event.Event.parse_and_raise(self.ctx.user.value)

        self.ctx.workstation.value = oils.utils.csedit.CSEditor().retrieve_actor_workstation(self.ctx.user.value.wsid())
        if not self.ctx.workstation.value:
            raise AuthException(_('No workstation found'))

    def fetch_work_orgs(self):
        work_orgs = osrf.ses.ClientSession.atomic_request(
            'open-ils.actor',
            'open-ils.actor.user.get_work_ous.ids',
            self.ctx.authtoken.value)
        oils.event.Event.parse_and_raise(work_orgs)
        return work_orgs

    def highest_work_perm_set(self, perm):
        perm_orgs = osrf.ses.ClientSession.atomic_request(
            'open-ils.actor',
            'open-ils.actor.user.work_perm.highest_org_set', self.ctx.authtoken.value, perm);
        self.ctx.high_perm_orgs.value[perm] = perm_orgs
        return perm_orgs

    def highest_work_perm_tree(self, perm):
        perm_orgs = self.highest_work_perm_set(perm)
        if len(perm_orgs) == 0:
            return None
        self.ctx.perm_tree.value[perm] = oils.org.OrgUtil.get_union_tree(perm_orgs)
        return self.ctx.perm_tree.value[perm]

    def fetch_user_setting(self, setting):
        setting = osrf.ses.ClientSession.atomic_request(
            oils.const.OILS_APP_ACTOR,
            'open-ils.actor.patron.settings.retrieve',
            self.ctx.authtoken.value, self.ctx.user.value.id(), setting)
        oils.event.Event.parse_and_raise(setting)
        return setting

    def get_date_format(self):
        setting = self.fetch_user_setting('common.date_format')
        if not setting:
            return '%Y-%m-%d'
        return setting

    def get_datetime_format(self):
        setting = self.fetch_user_setting('common.datetime_format')
        if not setting:
            return '%Y-%m-%d %H:%M'
        return setting


