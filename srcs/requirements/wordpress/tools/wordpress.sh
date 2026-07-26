#!/bin/sh

set -eu

if [ ! -f /var/www/html/wp-load.php ]; then
	echo "Downloading WordPress..."

	runuser -u www-data -- wp core download \
		--path=/var/www/html
else
	echo "WordPress files already exist."
fi

exec php-fpm8.2 -F
