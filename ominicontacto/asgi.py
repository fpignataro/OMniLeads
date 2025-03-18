# Copyright (C) 2018 Freetech Solutions

# This file is part of OMniLeads

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License version 3, as published by
# the Free Software Foundation.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.

# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see http://www.gnu.org/licenses/.
#
import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ominicontacto.settings')
django.setup()

from channels.http import AsgiHandler as get_asgi_application
from channels.routing import ProtocolTypeRouter
from channels.routing import URLRouter
from channels.auth import AuthMiddlewareStack
import notification_app.routing

if not os.getenv('WALLBOARD_VERSION', '') == '':
    import wallboard_app.routing

websocket_urlpatterns = []
websocket_urlpatterns.extend(notification_app.routing.websocket_urlpatterns)
if not os.getenv('WALLBOARD_VERSION', '') == '':
    websocket_urlpatterns.extend(wallboard_app.routing.websocket_urlpatterns)

application = ProtocolTypeRouter({
    "http": get_asgi_application(),
    "websocket": AuthMiddlewareStack(URLRouter(websocket_urlpatterns)),
})
