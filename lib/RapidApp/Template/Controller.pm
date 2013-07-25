package RapidApp::Template::Controller;
use strict;
use warnings;

use RapidApp::Include qw(sugar perlutil);
use Try::Tiny;
use Template;
use Module::Runtime;
use Path::Class qw(file dir);

# New unified controller for displaying and editing TT templates on a site-wide
# basis. This is an experiment that breaks with the previous RapidApp 'Module'
# design. It also is breaking away from DataStore2 for editing in order to support
# nested templates (i.e. tree structure instead of table/row structure)

use Moose;
with 'RapidApp::Role::AuthController';
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller' }

use RapidApp::Template::Context;
use RapidApp::Template::Provider;
use RapidApp::Template::Access;

has 'context_class', is => 'ro', default => 'RapidApp::Template::Context';
has 'provider_class', is => 'ro', default => 'RapidApp::Template::Provider';
has 'access_class', is => 'ro', default => 'RapidApp::Template::Access';
has 'access_params', is => 'ro', isa => 'HashRef', default => sub {{}};

has 'default_template_extension', is => 'ro', isa => 'Maybe[Str]', default => 'tt';

# If true, mouse-over edit controls will always be available for editable
# templates. Otherwise, query string ?editable=1 is required. Note that
# editable controls are *only* available in the context of an AutoPanel tab
has 'auto_editable', is => 'ro', isa => 'Bool', default => 0;

has 'Access', is => 'ro', lazy => 1, default => sub {
  my $self = shift;
  Module::Runtime::require_module($self->access_class);
  return $self->access_class->new({ 
    %{ $self->access_params },
    Controller => $self 
  });
}, isa => 'RapidApp::Template::Access';

# Maintain two separate Template instances - one that wraps divs and one that
# doesn't. Can't use the same one because compiled templates are cached
has 'Template_raw', is => 'ro', lazy => 1, default => sub {
  my $self = shift;
  return $self->_new_Template({ div_wrap => 0 });
}, isa => 'Template';

has 'Template_wrap', is => 'ro', lazy => 1, default => sub {
  my $self = shift;
  return $self->_new_Template({ div_wrap => 1 });
}, isa => 'Template';

sub _new_Template {
  my ($self,$opt) = @_;
  Module::Runtime::require_module($self->context_class);
  Module::Runtime::require_module($self->provider_class);
  return Template->new({ 
    CONTEXT => $self->context_class->new({
      Controller => $self,
      Access => $self->Access,
      STRICT => 1,
      LOAD_TEMPLATES => [
        $self->provider_class->new({
          Controller => $self,
          Access => $self->Access,
          #INCLUDE_PATH => $self->_app->default_tt_include_path,
          INCLUDE_PATH => [
            dir($self->_app->config->{home},'root/templates')->stringify,
            dir(RapidApp->share_dir,'templates')->stringify
          ],
          CACHE_SIZE => 64,
          %{ $opt || {} }
        })
      ] 
    })
  })
}

sub get_Provider {
  my $self = shift;
  return $self->Template_raw->context->{LOAD_TEMPLATES}->[0];
}

# Checks if the editable toggle/switch is on for this request. Note that
# this has *nothing* to do with actual editability of a given template,
# just whether or not edit controls should be available for templates that
# are allowed to be edited
sub is_editable_request {
  my ($self, $c) = @_;
  
  # check several mechanisms to turn on editing (mouse-over edit controls)
  return (
    $self->auto_editable ||
    $c->req->params->{editable} || 
    $c->req->params->{edit} ||
    $c->stash->{editable}
  );
}


## -----
## Top level alias URL paths 
#   TODO: add these programatically via config
#   see register_action_methods()
sub tpl :Path('/tpl') {
  my ($self, $c) = @_;
  $c->forward('view');
}

# Edit alias
sub tple :Path('/tple') {
  my ($self, $c) = @_;
  $c->stash->{editable} = 1;
  $c->forward('view');
}
## -----

sub _resolve_template_name {
  my ($self, @args) = @_;
  return undef unless (defined $args[0]);
  my $template = join('/',@args); 
  
  $template .= '.' . $self->default_template_extension if (
    $self->default_template_extension &&
    ! ( $template =~ /\./ ) #<-- doesn't contain a dot '.'
  );
  
  return $template;
}


# TODO: see about rendering with Catalyst::View::TT or a custom View
sub view :Local {
  my ($self, $c, @args) = @_;
  my $template = $self->_resolve_template_name(@args)
    or die "No template specified";
    
  local $self->{_current_context} = $c;
  
  $self->Access->template_viewable($template)
    or die "Permission denied - template '$template'";
  #  or return $self->_detach_response($c,403,"Permission denied - template '$template'");
  
  my $editable = $self->is_editable_request($c);
  
  my ($output,$content_type);
  
  my $ra_req = $c->req->headers->{'x-rapidapp-requestcontenttype'};
  if($ra_req && $ra_req eq 'JSON') {
    # This is a call from within ExtJS, wrap divs to id the templates from javascript
    my $html = $self->_render_template(
      $editable ? 'Template_wrap' : 'Template_raw',
      $template, $c
    );
    
    my $cnf = {
      xtype => 'panel',
      autoScroll => \1,
      bodyCssClass => 'ra-scoped-reset',
      
      # try to set the title/icon by finding/parsing <title> in the 'html'
      autopanel_parse_title => \1,
      
      # These will only be the title/icon if there is no parsable <title>
      tabTitle => join('/',@args), #<-- not using $template to preserve the orig req name
      tabIconCls => 'icon-page-white-world',
      
      template_controller_url => '/' . $self->action_namespace($c),
      html => $html
    };
    
    # No reason to load the plugin unless we're editable:
    $cnf->{plugins} = ['template-controller-panel'] if ($editable);
    
    # This is doing the same thing that the overly complex 'Module' controller does:
    $content_type = 'text/javascript; charset=utf-8';
    $output = encode_json_utf8($cnf);
  }
  else {
    # This is a direct browser call, need to include js/css
    my $text = join("\n",
      '<head>[% c.all_html_head_tags %]</head>',
      '<div class="ra-scoped-reset">',
      '[% INCLUDE ' . $template . ' %]',
      '</div>'
    );
    $content_type = 'text/html; charset=utf-8';
    $output = $self->_render_template('Template_raw',\$text,$c);
  }
  
  return $self->_detach_response($c,200,$output,$content_type);
}


# Read (not compiled/rendered) raw templates:
sub get :Local {
  my ($self, $c, @args) = @_;
  my $template = $self->_resolve_template_name(@args)
    or die "No template specified";
  
  local $self->{_current_context} = $c;
  
  $self->Access->template_readable($template)
    or return $self->_detach_response($c,403,"Permission denied - template '$template'");
  
  my ($data, $error) = $self->get_Provider->load($template);
  
  return $self->_detach_response($c,200,$data);
}

# Update raw templates:
sub set :Local {
  my ($self, $c, @args) = @_;
  my $template = $self->_resolve_template_name(@args)
    or die "No template specified";
  
  local $self->{_current_context} = $c;
  
  exists $c->req->params->{content}
    or return $self->_detach_response($c,400,"Template 'content' required");
  
  $self->Access->template_writable($template)
    or return $self->_detach_response($c,403,"Modify template '$template' - Permission denied");
  
  my $content = $c->req->params->{content};
  
  # Special status 418 means the supplied content is a bad template
  unless ($c->req->params->{skip_validate}) {
    my $err = $self->_get_template_error('Template_raw',\$content,$c);
    return $self->_detach_response($c,418,$err) if ($err);
  }
  
  $self->get_Provider->update_template($template,$content);
  
  return $self->_detach_response($c,200,'Template Updated');
}

sub create :Local {
  my ($self, $c, @args) = @_;
  my $template = $self->_resolve_template_name(@args)
    or die "No template specified";
  
  local $self->{_current_context} = $c;
  
  $self->Access->template_creatable($template)
    or return $self->_detach_response($c,403,"Create template '$template' - Permission denied");
  
  my $Provider = $self->get_Provider;
  
  die "Create template '$template' - already exists" 
    if $Provider->template_exists($template);
  
  $Provider->create_template($template)
    or die "Failed to create template '$template'";

  return $self->_detach_response($c,200,"Created template '$template'");
}

sub delete :Local {
  my ($self, $c, @args) = @_;
  my $template = $self->_resolve_template_name(@args)
    or die "No template specified";
  
  local $self->{_current_context} = $c;
  
  $self->Access->template_deletable($template)
    or return $self->_detach_response($c,403,"Delete template '$template' - Permission denied");
  
  my $Provider = $self->get_Provider;
  
  die "Delete template '$template' - doesn't exists" 
    unless $Provider->template_exists($template);
  
  $Provider->delete_template($template)
    or die "Failed to delete template '$template'";

  return $self->_detach_response($c,200,"Deleted template '$template'");
}

sub _detach_response {
  my ($self, $c, $status, $body, $content_type) = @_;
  $content_type ||= 'text/plain; charset=utf-8';
  $c->response->content_type($content_type);
  $c->response->status($status);
  $c->response->body($body);
  return $c->detach;
}

sub _render_template {
  my ($self, $meth, $template, $c) = @_;
  
  my $TT = $self->$meth;
  local $self->{_current_context} = $c;
  local $self->{_div_wrap} = 1 if ($meth eq 'Template_wrap');
  my $vars = $self->Access->get_template_vars($template);
  my $output;
  
  $output = $self->get_Provider->_template_error_content(
    $template, $TT->error, (
      $self->is_editable_request($c) &&
      $self->Access->template_writable($template)
    )
  ) unless $TT->process( $template, $vars, \$output );
  
  return $output;
}

# Returns undef if the template is valid or the error
sub _get_template_error {
  my ($self, $meth, $template, $c) = @_;
  my $TT = $self->$meth;
  local $self->{_current_context} = $c;
  local $self->{_div_wrap} = 1 if ($meth eq 'Template_wrap');
  my $vars = $self->Access->get_template_vars($template);
  my $output;
  return $TT->process( $template, $vars, \$output ) ? undef : $TT->error;
}


1;