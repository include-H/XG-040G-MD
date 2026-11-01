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

		m = new form.Map('iptv_multi', _('IPTV（多口）'),
			_('把一个或多个 LAN 口划给运营商的 IPTV VLAN。选中的口会从 br-lan 移到 br-iptv，未选中的口保留在主 LAN。'));

		s = m.section(form.NamedSection, 'config', 'iptv_multi');
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('启用'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'uplink', _('上联设备'),
			_('承载运营商 VLAN 的网口，通常是 pon0。'));
		o.default = 'pon0';
		o.rmempty = false;
		o.validate = function(sectionId, value) {
			return validIfname(value) || _('设备名不合法');
		};
		o.depends('enabled', '1');

		devices.forEach(function(dev) {
			var name = dev.getName();
			if (/^lan[0-9]+$/.test(name))
				lanPorts.push(name);
		});
		lanPorts.sort();

		o = s.option(form.DynamicList, 'lan_ports', _('IPTV LAN 口'),
			_('选中的口会从 br-lan 移到 br-iptv，接机顶盒。'));
		lanPorts.forEach(function(name) {
			o.value(name);
		});
		o.rmempty = false;
		o.depends('enabled', '1');

		o = s.option(form.Value, 'service_vlan', _('业务 VLAN'),
			_('承载 DHCP、认证、单播视频；没有单独组播 VLAN 时也承载组播。'));
		o.placeholder = '43';
		o.datatype = 'range(1,4094)';
		o.rmempty = false;
		o.depends('enabled', '1');

		o = s.option(form.Value, 'multicast_vlan', _('组播 VLAN（可选）'),
			_('只放行下行 IPv4 组播（224.0.0.0/4），并允许 IGMP 上行。留空表示使用业务 VLAN。'));
		o.placeholder = '40';
		o.datatype = 'range(1,4094)';
		o.rmempty = true;
		o.depends('enabled', '1');
		o.validate = function(sectionId, value) {
			var service = this.section.formvalue(sectionId, 'service_vlan');

			if (value && value === service)
				return _('组播 VLAN 与业务 VLAN 相同时请留空');

			return true;
		};

		o = s.option(form.Value, 'igmp_vlan', _('IGMP 上游 VLAN（可选）'),
			_('留空时使用组播 VLAN；没有组播 VLAN 时使用业务 VLAN。'));
		o.placeholder = _('与组播相同');
		o.datatype = 'range(1,4094)';
		o.rmempty = true;
		o.depends('enabled', '1');

		return m.render();
	}
});
