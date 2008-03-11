package OpenILS::Application::Acq::Financials;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Const qw/:const/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Event;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

# ----------------------------------------------------------------------------
# Funding Sources
# ----------------------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'create_funding_source',
	api_name	=> 'open-ils.acq.funding_source.create',
	signature => {
        desc => 'Creates a new funding_source',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'funding source object to create', type => 'object'}
        ],
        return => {desc => 'The ID of the new funding_source'}
    }
);

sub create_funding_source {
    my($self, $conn, $auth, $funding_source) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('ADMIN_FUNDING_SOURCE', $funding_source->owner);
    $e->create_acq_funding_source($funding_source) or return $e->die_event;
    $e->commit;
    return $funding_source->id;
}


__PACKAGE__->register_method(
	method => 'delete_funding_source',
	api_name	=> 'open-ils.acq.funding_source.delete',
	signature => {
        desc => 'Deletes a funding_source',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'funding source ID', type => 'number'}
        ],
        return => {desc => '1 on success, Event on failure'}
    }
);

sub delete_funding_source {
    my($self, $conn, $auth, $funding_source_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $funding_source = $e->retrieve_acq_funding_source($funding_source_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('ADMIN_FUNDING_SOURCE', $funding_source->owner, $funding_source);
    $e->delete_acq_funding_source($funding_source) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
	method => 'retrieve_funding_source',
	api_name	=> 'open-ils.acq.funding_source.retrieve',
	signature => {
        desc => 'Retrieves a new funding_source',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'funding source ID', type => 'number'}
        ],
        return => {desc => 'The funding_source object on success, Event on failure'}
    }
);

sub retrieve_funding_source {
    my($self, $conn, $auth, $funding_source_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $options ||= {};

    my $flesh = {flesh => 1, flesh_fields => {acqfs => []}};
    push(@{$flesh->{flesh_fields}->{acqfs}}, 'credits') if $$options{flesh_credits};
    push(@{$flesh->{flesh_fields}->{acqfs}}, 'allocations') if $$options{flesh_allocations};

    my $funding_source = $e->retrieve_acq_funding_source([$funding_source_id, $flesh]) or return $e->event;

    return $e->event unless $e->allowed(
        ['ADMIN_FUNDING_SOURCE','MANAGE_FUNDING_SOURCE', 'VIEW_FUNDING_SOURCE'], 
        $funding_source->owner, $funding_source); 

    $funding_source->summary(retrieve_funding_source_summary_impl($e, $funding_source))
        if $$options{flesh_summary};
    return $funding_source;
}

__PACKAGE__->register_method(
	method => 'retrieve_org_funding_sources',
	api_name	=> 'open-ils.acq.funding_source.org.retrieve',
	signature => {
        desc => 'Retrieves all the funding_sources associated with an org unit that the requestor has access to see',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'List of org Unit IDs.  If no IDs are provided, this method returns the 
                full set of funding sources this user has permission to view', type => 'number'},
            {desc => q/Limiting permission.  this permission is used find the work-org tree from which  
                the list of orgs is generated if no org ids are provided.  
                The default is ADMIN_FUNDING_SOURCE/, type => 'string'},
        ],
        return => {desc => 'The funding_source objects on success, empty array otherwise'}
    }
);

sub retrieve_org_funding_sources {
    my($self, $conn, $auth, $org_id_list, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $options ||= {};

    my $limit_perm = ($$options{limit_perm}) ? $$options{limit_perm} : 'ADMIN_FUNDING_SOURCE';
    return OpenILS::Event->new('BAD_PARAMS') 
        unless $limit_perm =~ /(ADMIN|MANAGE|VIEW)_FUNDING_SOURCE/;

    my $org_ids = ($org_id_list and @$org_id_list) ? $org_id_list :
        $U->find_highest_work_orgs($e, $limit_perm, {descendants =>1});

    return [] unless @$org_ids;
    my $sources = $e->search_acq_funding_source({owner => $org_ids});

    if($$options{flesh_summary}) {
        for my $source (@$sources) {
            $source->summary(retrieve_funding_source_summary_impl($e, $source));
        }
    }

    return $sources;
}

sub retrieve_funding_source_summary_impl {
    my($e, $source) = @_;
    my $at = $e->search_acq_funding_source_allocation_total({funding_source => $source->id})->[0];
    my $b = $e->search_acq_funding_source_balance({funding_source => $source->id})->[0];
    my $ct = $e->search_acq_funding_source_credit_total({funding_source => $source->id})->[0];
    return {
        allocation_total => ($at) ? $at->amount : 0,
        balance => ($b) ? $b->amount : 0,
        credit_total => ($ct) ? $ct->amount : 0,
    };
}


__PACKAGE__->register_method(
	method => 'create_funding_source_credit',
	api_name	=> 'open-ils.acq.funding_source_credit.create',
	signature => {
        desc => 'Create a new funding source credit',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'funding source credit object', type => 'object'}
        ],
        return => {desc => 'The ID of the new funding source credit on success, Event on failure'}
    }
);

sub create_funding_source_credit {
    my($self, $conn, $auth, $fs_credit) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->event unless $e->checkauth;

    my $fs = $e->retrieve_acq_funding_source($fs_credit->funding_source)
        or return $e->die_event;
    return $e->die_event unless $e->allowed(['MANAGE_FUNDING_SOURCE'], $fs->owner, $fs); 

    $e->create_acq_funding_source_credit($fs_credit) or return $e->die_event;
    $e->commit;
    return $fs_credit->id;
}


# ---------------------------------------------------------------
# funds
# ---------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'create_fund',
	api_name	=> 'open-ils.acq.fund.create',
	signature => {
        desc => 'Creates a new fund',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund object to create', type => 'object'}
        ],
        return => {desc => 'The ID of the newly created fund object'}
    }
);

sub create_fund {
    my($self, $conn, $auth, $fund) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('ADMIN_FUND', $fund->org);
    $e->create_acq_fund($fund) or return $e->die_event;
    $e->commit;
    return $fund->id;
}


__PACKAGE__->register_method(
	method => 'delete_fund',
	api_name	=> 'open-ils.acq.fund.delete',
	signature => {
        desc => 'Deletes a fund',
        params => {
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund ID', type => 'number'}
        },
        return => {desc => '1 on success, Event on failure'}
    }
);

sub delete_fund {
    my($self, $conn, $auth, $fund_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $fund = $e->retrieve_acq_fund($fund_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('ADMIN_FUND', $fund->org, $fund);
    $e->delete_acq_fund($fund) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
	method => 'retrieve_fund',
	api_name	=> 'open-ils.acq.fund.retrieve',
	signature => {
        desc => 'Retrieves a new fund',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund ID', type => 'number'}
        ],
        return => {desc => 'The fund object on success, Event on failure'}
    }
);

sub retrieve_fund {
    my($self, $conn, $auth, $fund_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $options ||= {};

    my $flesh = {flesh => 2, flesh_fields => {acqf => []}};
    push(@{$flesh->{flesh_fields}->{acqf}}, 'debits') if $$options{flesh_debits};
    push(@{$flesh->{flesh_fields}->{acqf}}, 'allocations') if $$options{flesh_allocations};
    push(@{$flesh->{flesh_fields}->{acqfa}}, 'funding_source') if $$options{flesh_allocation_sources};

    my $fund = $e->retrieve_acq_fund([$fund_id, $flesh]) or return $e->event;
    return $e->event unless $e->allowed(['ADMIN_FUND','MANAGE_FUND', 'VIEW_FUND'], $fund->org, $fund);
    $fund->summary(retrieve_fund_summary_impl($e, $fund))
        if $$options{flesh_summary};
    return $fund;
}

__PACKAGE__->register_method(
	method => 'retrieve_org_funds',
	api_name	=> 'open-ils.acq.fund.org.retrieve',
	signature => {
        desc => 'Retrieves all the funds associated with an org unit',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'List of org Unit IDs.  If no IDs are provided, this method returns the 
                full set of funding sources this user has permission to view', type => 'number'},
            {desc => q/Options hash.  
                "limit_perm" -- this permission is used find the work-org tree from which  
                the list of orgs is generated if no org ids are provided.  The default is ADMIN_FUND.
                "flesh_summary" -- if true, the summary field on each fund is fleshed
                The default is ADMIN_FUND/, type => 'string'},
        ],
        return => {desc => 'The fund objects on success, Event on failure'}
    }
);

sub retrieve_org_funds {
    my($self, $conn, $auth, $org_id_list, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $options ||= {};

    my $limit_perm = ($$options{limit_perm}) ? $$options{limit_perm} : 'ADMIN_FUND';
    return OpenILS::Event->new('BAD_PARAMS') 
        unless $limit_perm =~ /(ADMIN|MANAGE|VIEW)_FUND/;

    my $org_ids = ($org_id_list and @$org_id_list) ? $org_id_list :
        $U->find_highest_work_orgs($e, $limit_perm, {descendants =>1});
    return [] unless @$org_ids;
    my $funds = $e->search_acq_fund({org => $org_ids});

    if($$options{flesh_summary}) {
        for my $fund (@$funds) {
            $fund->summary(retrieve_fund_summary_impl($e, $fund));
        }
    }

    return $funds;
}

__PACKAGE__->register_method(
	method => 'retrieve_fund_summary',
	api_name	=> 'open-ils.acq.fund.summary.retrieve',
	signature => {
        desc => 'Returns a summary of credits/debits/encumberances for a fund',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund id', type => 'number' }
        ],
        return => {desc => 'A hash of summary information, Event on failure'}
    }
);

sub retrieve_fund_summary {
    my($self, $conn, $auth, $fund_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $fund = $e->retrieve_acq_fund($fund_id) or return $e->event;
    return $e->event unless $e->allowed('MANAGE_FUND', $fund->org, $fund);
    return retrieve_fund_summary_impl($e, $fund);
}


sub retrieve_fund_summary_impl {
    my($e, $fund) = @_;

    my $at = $e->search_acq_fund_allocation_total({fund => $fund->id})->[0];
    my $dt = $e->search_acq_fund_debit_total({fund => $fund->id})->[0];
    my $et = $e->search_acq_fund_encumberance_total({fund => $fund->id})->[0];
    my $st = $e->search_acq_fund_spent_total({fund => $fund->id})->[0];
    my $cb = $e->search_acq_fund_combined_balance({fund => $fund->id})->[0];
    my $sb = $e->search_acq_fund_spent_balance({fund => $fund->id})->[0];

    return {
        allocation_total => ($at) ? $at->amount : 0,
        debit_total => ($dt) ? $dt->amount : 0,
        encumberance_total => ($et) ? $et->amount : 0,
        spent_total => ($st) ? $st->amount : 0,
        combined_balance => ($cb) ? $cb->amount : 0,
        spent_balance => ($sb) ? $sb->amount : 0,
    };
}


# ---------------------------------------------------------------
# fund Allocations
# ---------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'create_fund_alloc',
	api_name	=> 'open-ils.acq.fund_allocation.create',
	signature => {
        desc => 'Creates a new fund_allocation',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund allocation object to create', type => 'object'}
        ],
        return => {desc => 'The ID of the new fund_allocation'}
    }
);

sub create_fund_alloc {
    my($self, $conn, $auth, $fund_alloc) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    # this action is equivalent to both debiting a funding source and crediting a fund

    my $source = $e->retrieve_acq_funding_source($fund_alloc->funding_source)
        or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUNDING_SOURCE', $source->owner);

    my $fund = $e->retrieve_acq_fund($fund_alloc->fund) or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUND', $fund->org, $fund);

    $fund_alloc->allocator($e->requestor->id);
    $e->create_acq_fund_allocation($fund_alloc) or return $e->die_event;
    $e->commit;
    return $fund_alloc->id;
}


__PACKAGE__->register_method(
	method => 'delete_fund_alloc',
	api_name	=> 'open-ils.acq.fund_allocation.delete',
	signature => {
        desc => 'Deletes a fund_allocation',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund Alocation ID', type => 'number'}
        ],
        return => {desc => '1 on success, Event on failure'}
    }
);

sub delete_fund_alloc {
    my($self, $conn, $auth, $fund_alloc_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $fund_alloc = $e->retrieve_acq_fund_allocation($fund_alloc_id) or return $e->die_event;

    my $source = $e->retrieve_acq_funding_source($fund_alloc->funding_source)
        or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUNDING_SOURCE', $source->owner, $source);

    my $fund = $e->retrieve_acq_fund($fund_alloc->fund) or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUND', $fund->org, $fund);

    $e->delete_acq_fund_allocation($fund_alloc) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
	method => 'retrieve_fund_alloc',
	api_name	=> 'open-ils.acq.fund_allocation.retrieve',
	signature => {
        desc => 'Retrieves a new fund_allocation',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund Allocation ID', type => 'number'}
        ],
        return => {desc => 'The fund allocation object on success, Event on failure'}
    }
);

sub retrieve_fund_alloc {
    my($self, $conn, $auth, $fund_alloc_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $fund_alloc = $e->retrieve_acq_fund_allocation($fund_alloc_id) or return $e->event;

    my $source = $e->retrieve_acq_funding_source($fund_alloc->funding_source)
        or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUNDING_SOURCE', $source->owner, $source);

    my $fund = $e->retrieve_acq_fund($fund_alloc->fund) or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUND', $fund->org, $fund);

    return $fund_alloc;
}


__PACKAGE__->register_method(
	method => 'retrieve_funding_source_allocations',
	api_name	=> 'open-ils.acq.funding_source.allocations.retrieve',
	signature => {
        desc => 'Retrieves a new fund_allocation',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund Allocation ID', type => 'number'}
        ],
        return => {desc => 'The fund allocation object on success, Event on failure'}
    }
);

sub retrieve_funding_source_allocations {
    my($self, $conn, $auth, $fund_alloc_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $fund_alloc = $e->retrieve_acq_fund_allocation($fund_alloc_id) or return $e->event;

    my $source = $e->retrieve_acq_funding_source($fund_alloc->funding_source)
        or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUNDING_SOURCE', $source->owner, $source);

    my $fund = $e->retrieve_acq_fund($fund_alloc->fund) or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUND', $fund->org, $fund);

    return $fund_alloc;
}

# ----------------------------------------------------------------------------
# Currency
# ----------------------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'retrieve_all_currency_type',
	api_name	=> 'open-ils.acq.currency_type.all.retrieve',
	signature => {
        desc => 'Retrieves all currency_type objects',
        params => [
            {desc => 'Authentication token', type => 'string'},
        ],
        return => {desc => 'List of currency_type objects', type => 'list'}
    }
);

sub retrieve_all_currency_type {
    my($self, $conn, $auth, $fund_alloc_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('GENERAL_ACQ');
    return $e->retrieve_all_acq_currency_type();
}

sub currency_conversion_impl {
    my($src_currency, $dest_currency, $amount) = @_;
    my $result = new_editor()->json_query({
        select => {
            acqct => [{
                params => [$dest_currency, $amount],
                transform => 'acq.exchange_ratio',
                column => 'code',
                alias => 'value'
            }]
        },
        where => {code => $src_currency},
        from => 'acqct'
    });

    return $result->[0]->{value};
}


# ----------------------------------------------------------------------------
# Purchase Orders
# ----------------------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'create_purchase_order',
	api_name	=> 'open-ils.acq.purchase_order.create',
	signature => {
        desc => 'Creates a new purchase order',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'purchase_order to create', type => 'object'}
        ],
        return => {desc => 'The purchase order id, Event on failure'}
    }
);

sub create_purchase_order {
    my($self, $conn, $auth, $p_order) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    $p_order->owner($e->requestor->id);

    my $provider = $e->retrieve_acq_provider($p_order->provider)
        or return $e->die_event;

    $p_order->ordering_agency($e->requestor->ws_ou) or return $e->die_event;

    return $e->die_event unless $e->allowed('MANAGE_PROVIDER', $provider->owner, $provider);

    $e->create_acq_purchase_order($p_order) or return $e->die_event;
    $e->commit;
    return $p_order->id;
}

__PACKAGE__->register_method(
	method => 'retrieve_all_user_purchase_order',
	api_name	=> 'open-ils.acq.purchase_order.user.all.retrieve',
    stream => 1,
	signature => {
        desc => 'Retrieves a purchase order',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'purchase_order to retrieve', type => 'number'},
            {desc => q/Options hash.  flesh_lineitems: to get the lineitems and lineitem_attrs; 
                clear_marc: to clear the MARC data from the lineitem (for reduced bandwidth);
                limit: number of items to return ,defaults to 50;
                offset: offset in the list of items to return
                order_by: sort the result, provide one or more colunm names, separated by commas,
                optionally followed by ASC or DESC as a single string 
                li_limit : number of lineitems to return if fleshing line items;
                li_offset : lineitem offset if fleshing line items
                li_order_by : lineitem sort definition if fleshing line items
                flesh_lineitem_detail_count : flesh lineitem_detail_count field
                /,
                type => 'hash'}
        ],
        return => {desc => 'The purchase order, Event on failure'}
    }
);

sub retrieve_all_user_purchase_order {
    my($self, $conn, $auth, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $options ||= {};

    # grab purchase orders I have 
    my $perm_orgs = $U->find_highest_work_orgs($e, 'MANAGE_PROVIDER', {descendants =>1});
	return OpenILS::Event->new('PERM_FAILURE', ilsperm => 'MANAGE_PROVIDER')
        unless @$perm_orgs;
    my $provider_ids = $e->search_acq_provider({owner => $perm_orgs}, {idlist=>1});
    my $po_ids = $e->search_acq_purchase_order({provider => $provider_ids}, {idlist=>1});

    # grab my purchase orders
    push(@$po_ids, @{$e->search_acq_purchase_order({owner => $e->requestor->id}, {idlist=>1})});

    return undef unless @$po_ids;

    # now get the db to limit/sort for us
    $po_ids = $e->search_acq_purchase_order(
        [   {id => $po_ids}, {
                limit => $$options{limit} || 50,
                offset => $$options{offset} || 0,
                order_by => {acqpo => $$options{order_by} || 'create_time'}
            }
        ],
        {idlist => 1}
    );

    $conn->respond(retrieve_purchase_order_impl($e, $_, $options)) for @$po_ids;
    return undef;
}

__PACKAGE__->register_method(
	method => 'retrieve_purchase_order',
	api_name	=> 'open-ils.acq.purchase_order.retrieve',
	signature => {
        desc => 'Retrieves a purchase order',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'purchase_order to retrieve', type => 'number'},
            {desc => q/Options hash.  flesh_lineitems, to get the lineitems and lineitem_attrs; 
                clear_marc, to clear the MARC data from the lineitem (for reduced bandwidth)
                li_limit : number of lineitems to return if fleshing line items;
                li_offset : lineitem offset if fleshing line items
                li_order_by : lineitem sort definition if fleshing line items
                /, 
                type => 'hash'}
        ],
        return => {desc => 'The purchase order, Event on failure'}
    }
);

sub retrieve_purchase_order {
    my($self, $conn, $auth, $po_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event if po_perm_failure($e, $po_id);
    return retrieve_purchase_order_impl($e, $po_id, $options);
}


# if the user does not have permission to perform actions on this PO, return the perm failure event
sub po_perm_failure {
    my($e, $po_id, $fund_id) = @_;
    my $po = $e->retrieve_acq_purchase_order($po_id) or return $e->event;
    my $provider = $e->retrieve_acq_provider($po->provider) or return $e->event;
    return $e->event unless $e->allowed('MANAGE_PROVIDER', $provider->owner, $provider);
    if($fund_id) {
        my $fund = $e->retrieve_acq_fund($po->$fund_id);
        return $e->event unless $e->allowed('MANAGE_FUND', $fund->org, $fund);
    }
    return undef;
}


sub retrieve_purchase_order_impl {
    my($e, $po_id, $options) = @_;

    $options ||= {};
    my $po = $e->retrieve_acq_purchase_order($po_id) or return $e->event;

    if($$options{flesh_lineitems}) {
        my $items = $e->search_acq_lineitem([
            {purchase_order => $po_id},
            {
                flesh => 1,
                flesh_fields => {
                    jub => ['attributes']
                },
                limit => $$options{li_limit} || 50,
                offset => $$options{li_offset} || 0,
                order_by => {jub => $$options{li_order_by} || 'create_time'}
            }
        ]);

        if($$options{clear_marc}) {
            $_->clear_marc for @$items;
        }

        $po->lineitems($items);
    }

    if($$options{flesh_lineitem_count}) {
        my $items = $e->search_acq_lineitem({purchase_order => $po_id}, {idlist=>1});
        $po->lineitem_count(scalar(@$items));
    }

    return $po;
}


=head
__PACKAGE__->register_method(
	method => 'create_lineitem',
	api_name	=> 'open-ils.acq.lineitem.create',
	signature => {
        desc => 'Creates a new purchase order line item',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'purchase order line item to create', type => 'object'},
            {desc => q/Options hash.  picklist_entry (required) is the id of the 
                picklist_entry object used as the reference for this line item/, type => 'hash'}
        ],
        return => {desc => 'The purchase order line item id, Event on failure'}
    }
);

sub create_lineitem {
    my($self, $conn, $auth, $li, $options) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    $options ||= {};

    return $e->die_event if po_perm_failure($e, $li->purchase_order);

    # if a picklist_entry ID is provided, use that as the basis for this item
    my $ple = $e->retrieve_acq_picklist_entry([
        $$options{picklist_entry}, 
        {flesh => 1, flesh_fields => {acqple => ['attributes']}}
    ]) or return $e->die_event;

    $li->marc($ple->marc);
    $li->eg_bib_id($ple->eg_bib_id);
    $e->create_acq_lineitem($li) or return $e->die_event;

    for my $plea (@{$ple->attributes}) {
        # now that we have the line item, copy the attributes over from the picklist entry
        my $attr = Fieldmapper::acq::li_attr->new;
        $attr->attr_type($plea->attr_type);
        $attr->attr_value($plea->attr_value);
        $attr->attr_name($plea->attr_name);
        $attr->lineitem($li->id);
        $e->create_acq_li_attr($attr) or return $e->die_event;
    }

    # update the picklist entry and point it to the line item
    $ple->lineitem($li->id);
    $ple->edit_time('now');
    $e->update_acq_picklist_entry($ple) or return $e->die_event;

    $e->commit;
    return $li->id;
}
=cut


__PACKAGE__->register_method(
	method => 'create_lineitem_detail',
	api_name	=> 'open-ils.acq.lineitem_detail.create',
	signature => {
        desc => q/Creates a new purchase order line item detail.  
            Additionally creates the associated fund_debit/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem_detail to create', type => 'object'},
            {desc => q/Options hash.  fund_id, the fund funding this line item
                price, the price we are paying the vendor, in the vendor's currency/, type => 'hash'}
        ],
        return => {desc => 'The purchase order line item detail id, Event on failure'}
    }
);

sub create_lineitem_detail {
    my($self, $conn, $auth, $li_detail, $options) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    $options ||= {};

    my $li = $e->retrieve_acq_lineitem($li_detail->lineitem)
        or return $e->die_event;

    # XXX check lineitem provider perms

    if($li_detail->fund) {
        my $fund = $e->retrieve_acq_fund($li_detail->fund) or return $e->die_event;
        return $e->die_event unless 
            $e->allowed('MANAGE_FUND', $fund->org, $fund);
    }

=head XXX move to new method
    my $fct = $e->search_acq_currency_type({code => $fund->currency_type})->[0];
    my $pct = $e->search_acq_currency_type({code => $provider->currency_type})->[0];
    my $price = $$options{price};
    # create the fund_debit for this line item detail
    my $fdebit = Fieldmapper::acq::fund_debit->new;
    $fdebit->fund($$options{fund_id});
    $fdebit->origin_amount($price);
    $fdebit->origin_currency_type($pct->code); # == vendor's currency
    $fdebit->encumberance('t');
    $fdebit->debit_type(OILS_ACQ_DEBIT_TYPE_PURCHASE);
    $fdebit->amount(currency_conversion_impl($pct->code, $fct->code, $price));
    $e->create_acq_fund_debit($fdebit) or return $e->die_event;

    $li_detail->fund_debit($fdebit->id);
=cut

    $e->create_acq_lineitem_detail($li_detail) or return $e->die_event;
    $e->commit;
    return $li_detail->id;
}


=head
__PACKAGE__->register_method(
	method => 'retrieve_lineitem',
	api_name	=> 'open-ils.acq.lineitem.retrieve',
	signature => {
        desc => q/Retrieve a lineitem/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem ID', type => 'number'},
            {desc => q/Options hash. flesh_li_details: fleshes the details objects, which
                additionally flesh the fund_debit and fund objects/, 
                type => 'hash'}
        ],
        return => {desc => 'The lineitem object, Event on failure'}
    }
);

sub retrieve_lineitem {
    my($self, $conn, $auth, $li_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $options ||= {};

    my $li = $e->retrieve_acq_lineitem([
        $li_id, 
        {   flesh => 1,
            flesh_fields => {
                jub => ['attributes']
            },
        }
    ]) or return $e->event;

    return $e->die_event if po_perm_failure($e, $li->purchase_order);

    if($$options{flesh_li_details}) {
        my $details = $e->search_acq_li_detail([
            {lineitem => $li_id}, {
                flesh => 1,
                flesh_fields => {acqlid => ['fund_debit', 'fund']}
            }
        ]);
        $li->lineitem_details($details);
    }


    if($$options{flesh_li_attrs}) {
        my $attrs = $e->search_acq_li_attr({lineitem => $li_id});
        $li->attributes($attrs);
    }

    $li->clear_marc if $$options{clear_marc};
    return $li;
}
=cut

__PACKAGE__->register_method(
	method => 'update_lineitem_detail',
	api_name	=> 'open-ils.acq.lineitem_detail.update',
	signature => {
        desc => q/Updates a lineitem detail/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem_detail to update', type => 'object'},
        ],
        return => {desc => '1 on success, Event on failure'}
    }
);

sub update_lineitem_detail {
    my($self, $conn, $auth, $li_detail) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    if($li_detail->fund) {
        my $fund = $e->retrieve_acq_fund($li_detail->fund) or return $e->die_event;
        return $e->die_event unless 
            $e->allowed('MANAGE_FUND', $fund->org, $fund);
    }

    # XXX check lineitem perms

    $e->update_acq_lineitem_detail($li_detail) or return $e->die_event;
    $e->commit;
    return 1;
}


__PACKAGE__->register_method(
	method => 'retrieve_lineitem_detail',
	api_name	=> 'open-ils.acq.lineitem_detail.retrieve',
	signature => {
        desc => q/Updates a lineitem detail/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem_detail to retrieve', type => 'object'},
        ],
        return => {desc => '1 on success, Event on failure'}
    }
);
sub retrieve_lineitem_detail {
    my($self, $conn, $auth, $li_detail_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    my $li_detail = $e->retrieve_acq_lineitem_detail($li_detail_id)
        or return $e->event;

    if($li_detail->fund) {
        my $fund = $e->retrieve_acq_fund($li_detail->fund) or return $e->event;
        return $e->event unless 
            $e->allowed('MANAGE_FUND', $fund->org, $fund);
    }

    # XXX check lineitem perms
    return $li_detail;
}
1;

