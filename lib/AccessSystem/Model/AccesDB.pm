package AccessSystem::Model::AccesDB;

use strict;
use base 'Catalyst::Model::DBIC::Schema';

__PACKAGE__->config(
    schema_class => 'AccessSystem::Schema',
    
    connect_info => {
        dsn => 'dbi:SQLite:db/test.db',
        user => '',
        password => '',
    }
);

=head1 NAME

AccessSystem::Model::AccesDB - Catalyst DBIC Schema Model

=head1 SYNOPSIS

See L<AccessSystem>

=head1 DESCRIPTION

L<Catalyst::Model::DBIC::Schema> Model using schema L<AccessSystem::Schema>

=head1 GENERATED BY

Catalyst::Helper::Model::DBIC::Schema - 0.65

=head1 AUTHOR

A clever guy

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
