// SPDX-License-Identifier: Apache-2.0
'use strict';
'require form';
'require network';
'require view';

function validIfname(value) {
	return /^[A-Za-z0-9_.:-]{1,15}$/.test(value || '');
}

return view.extend({
	load: function() {
		return network.getDevices();
	},

	render: function(devices) {
		var m, s, o, lanPorts = [];

		m = new form.Map('iptv_multi', _('IPTV (multi-port)'),
			_('Bind one or more LAN ports to the operator IPTV VLANs. Selected ports are removed from br-lan; ports not selected stay in the main LAN.'));

		s = m.section(form.NamedSection, 'config', 'iptv_multi');
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'uplink', _('Uplink device'),
			_('Network device carrying the operator VLANs, normally pon0.'));
		o.default = 'pon0';
		o.rmempty = false;
		o.validate = function(sectionId, value) {
			return validIfname(value) || _('Invalid device name');
		};
		o.depends('enabled', '1');

		devices.forEach(function(dev) {
			var name = dev.getName();
			if (/^lan[0-9]+$/.test(name))
				lanPorts.push(name);
		});
		lanPorts.sort();

		o = s.option(form.DynamicList, 'lan_ports', _('IPTV LAN ports'),
			_('Selected ports are moved from br-lan to br-iptv.'));
		lanPorts.forEach(function(name) {
			o.value(name);
		});
		o.rmempty = false;
		o.depends('enabled', '1');

		o = s.option(form.Value, 'service_vlan', _('Service VLAN'),
			_('Carries DHCP, authentication, unicast video and, without a separate multicast VLAN, multicast.'));
		o.placeholder = '43';
		o.datatype = 'range(1,4094)';
		o.rmempty = false;
		o.depends('enabled', '1');

		o = s.option(form.Value, 'multicast_vlan', _('Multicast VLAN (optional)'),
			_('Downstream IPv4 multicast; IGMP is allowed upstream. Leave empty to use the service VLAN.'));
		o.placeholder = '40';
		o.datatype = 'range(1,4094)';
		o.rmempty = true;
		o.depends('enabled', '1');
		o.validate = function(sectionId, value) {
			var service = this.section.formvalue(sectionId, 'service_vlan');

			if (value && value === service)
				return _('Leave empty when multicast uses the service VLAN.');

			return true;
		};

		o = s.option(form.Value, 'igmp_vlan', _('IGMP upstream VLAN (optional)'),
			_('Leave empty to use the multicast VLAN, or the service VLAN when no multicast VLAN is set.'));
		o.placeholder = _('Same as multicast');
		o.datatype = 'range(1,4094)';
		o.rmempty = true;
		o.depends('enabled', '1');

		return m.render();
	}
});
