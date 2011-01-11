package RapidApp::Web1RenderContext::ExtCfgToHtml;
use Moose;
extends 'RapidApp::Web1RenderContext::RenderByType';
with 'RapidApp::Web1RenderContext::ExtCfgToHtml::Basic';
with 'RapidApp::Web1RenderContext::ExtCfgToHtml::Form';

use RapidApp::Include 'perlutil', 'sugar';

has 'rendererByXtype' => (
	traits  => ['Hash'],
	is      => 'ro',
	isa     => 'HashRef',
	default => sub { {} },
	handles => { apply_rendererByXtype => 'set', },
);

has '_rendererByXtypeCache' => ( is => 'ro', isa => 'HashRef', default => sub { {} } );

=head2 renderAsHtml

We subclass RenderByType to first check if the data is a plain hash, and if so,
whether it has a renderer (indicated by ->{rapidapp_cfg2html_renderer}) or
if it has an xtype that we have a renderer for.

This functionality is performed by ->findRendererForExtCfg

Else we pass it on to the superclass (where blessed things get taken care of).

=cut
sub renderAsHtml {
	my ($self, $renderCxt, $data)= @_;
	if (ref $data eq 'HASH') {
		my $renderer= $self->findRendererForExtCfg($data);
		defined $renderer
			and return $renderer->renderAsHtml($renderCxt, $data);
		RapidApp::ScopedGlobals->log->warn('No renderer defined for xtype "'.$data->{xtype}.'"');
	}
	return $self->SUPER::renderAsHtml($renderCxt, $data);
}

sub findRendererForExtCfg {
	my ($self, $extCfg)= @_;
	# first, see if a renderer was specified, else, render based on xtype
	return $extCfg->{rapidapp_cfg2html_renderer} || $self->findRendererForXtype($extCfg->{xtype});
}

sub findRendererForXtype {
	my ($self, $extCfg)= @_;
	
	my $xtype= $extCfg->{xtype};
	defined $xtype or return undef;
	
	# see if it is cached
	return $self->_rendererByXtypeCache->{$xtype}
		# or if not, see if it was specified or if a function is defined for it, and cache it.
		|| ($self->_rendererByXtypeCache->{$xtype}=
				($self->rendererByXtype->{$xtype} || $self->makeRendererForMethod('render_xtype_'.$xtype))
			);
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;
