# -*- coding: utf-8 -*-
# Copyright (C) 2018 Freetech Solutions

import websocket
import threading
import time
import logging
import json
import ssl
import os
import datetime
import gc
import redis
import psycopg2

OMNILEADS_HOSTNAME = os.environ.get('OMNILEADS_HOSTNAME') or 'localhost'
WSURL = f'wss://{OMNILEADS_HOSTNAME}/consumers/stream/survey_app/answers/updates'
QUEUE_KEY = 'OML:QUEUE:CALL_CUSTOM_VAR'

logger = logging.getLogger("asyncio")
INSTALL_PREFIX = os.getenv('INSTALL_PREFIX')
fh = logging.FileHandler(f'{INSTALL_PREFIX}/log/call_custom_var.log')

logger.addHandler(fh)
logger.setLevel(logging.INFO)
websocket.enableTrace(False)


class WebsocketClient(object):
    """ Se suscribe al stream de notificaciones de que se encoló un CallCustomVarLog
        Al llegar cada notificación intenta persistir los logs encolados en
        QUEUE_KEY a PostgreSQL
    """
    def __init__(self, ws_url, redis_connection, logger):
        super().__init__()
        self.ws_url = ws_url
        self.logger = logger
        self.persistidor = PersistidorCallCustomVarLog(redis_connection, logger)

    def run_forever(self):
        self._start_websocket_client()
        self.ws.run_forever(
            skip_utf8_validation=True, sslopt={"cert_reqs": ssl.CERT_NONE})

    def on_message(self, ws, message):
        # No me interesa el mensaje, solo saber que hay logs encolados
        self.persistidor.persistir()

    def on_error(self, ws, error):
        self.logger.error(self._log_msg(error))

    def on_open(self, ws):
        CONN_LOG = 'Websocket connected'
        self.logger.info(self._log_msg(CONN_LOG))

    def on_close(self, ws):
        CONN_LOG = 'Websocket connection closed'
        self.logger.error(self._log_msg(CONN_LOG))

    def _start_websocket_client(self):
        self.ws = websocket.WebSocketApp(self.ws_url,
                                         on_message=self.on_message,
                                         on_error=self.on_error,
                                         on_close=self.on_close)
        self.ws.on_open = self.on_open

    def start(self):
        RESTARTING_LOG = 'Reconnecting after 5 secs'
        while True:
            try:
                wst = threading.Thread(target=self.run_forever())
                wst.daemon = True
                wst.start()
            except Exception as e:
                gc.collect()
                self.logger.error(self._log_msg(e))
            self.logger.info(self._log_msg(RESTARTING_LOG))
            time.sleep(10)

    def _log_msg(self, message):
        return f'{datetime.datetime.now()}:-{message}'


class PersistidorCallCustomVarLog(object):

    def __init__(self, redis_connection, logger):
        super().__init__()
        self.redis_connection = redis_connection
        self.logger = logger
        self.pg_connection = None

    def _get_db_cursor(self):
        if self.pg_connection:
            return self.pg_connection.cursor()
        self.pg_connection = psycopg2.connect(
            host=os.getenv('PGHOST'), dbname=os.getenv('PGDATABASE'),
            user=os.getenv('PGUSER'), port=os.getenv('PGPORT'), password=os.getenv('PGPASSWORD'))
        return self.pg_connection.cursor()

    def persistir(self):
        try:
            items = self.redis_connection.lrange(QUEUE_KEY, 0, -1)
            self.redis_connection.ltrim(QUEUE_KEY, len(items), -1)
        except Exception as e:
            self.logger.error(self._log_msg('Fallo del comando: {0}'.format(e)))
        else:
            for item_json in items:
                try:
                    self._persistir_item(json.loads(item_json))
                except (psycopg2.ProgrammingError, psycopg2.IntegrityError):
                    self.logger.info(self._log_msg('INVALID LOG DATA: ' + item_json))
                except Exception:
                    self.logger.info(self._log_msg('LOG DATA PROBLEM: ' + item_json))
            if items:
                try:
                    self.pg_connection.commit()
                except (psycopg2.ProgrammingError, psycopg2.IntegrityError):
                    self.logger.info(self._log_msg('INVALID LOG DATA: ' + item_json))
                except Exception:
                    self.logger.info(self._log_msg('LOG DATA PROBLEM: ' + item_json))

    def _persistir_item(self, item):
        callid = item[0]
        valor = item[1]

        sql = """INSERT INTO public.reportes_app_callcustomvarlog(callid, valor)
            VALUES (%s, %s);
        """
        params = (callid, valor)
        cursor = self._get_db_cursor()
        cursor.execute(sql, params)

    def _log_msg(self, message):
        return f'{datetime.datetime.now()}:-{message}'


RG_SCRIPT = """
def notify_stream(x):
    print('NOTIFY STREAM')
    print(x)
    execute('XADD', 'reportes_app_callcustomvarlog_updates', 'MAXLEN', '~', 1, '*', 'value', '1')


gb = GearsBuilder(desc='reportes_callcustomvarlog_notification')
gb.foreach(notify_stream)
gb.register("OML:QUEUE:CALL_CUSTOM_VAR")
"""


class RedisGearsService(object):
    """ Registra un  """

    def __init__(self, redis_connection):
        self.redis_connection = redis_connection

    def __existe_evento_add_queue(self):
        DESC = 'reportes_callcustomvarlog_notification'
        REGISTRATION_DATA = 7  # Posicion "RegistrationData" en datos de registro
        ARGS = 13  # Posicion "args" en "RegistrationData"
        REGEX = 1  # Pos "regex" en "args"
        P_DESC = 5  # Posicion "desc" en datos de registro
        lista_eventos_registrados = self.redis_connection.execute_command("RG.DUMPREGISTRATIONS")
        for evento in lista_eventos_registrados:
            regex_evento = evento[REGISTRATION_DATA][ARGS][REGEX]
            if regex_evento == QUEUE_KEY and evento[P_DESC] == DESC:
                return True
        return False

    def registrar_evento_encolar_log(self):
        if not self.__existe_evento_add_queue():
            self.redis_connection.execute_command("RG.PYEXECUTE", RG_SCRIPT)


def start():
    redis_connection = redis.Redis(
        host=os.getenv('REDIS_HOSTNAME'),
        port=6379,  # settings.CONSTANCE_REDIS_CONNECTION['port'],
        decode_responses=True)
    rg_service = RedisGearsService(redis_connection)
    rg_service.registrar_evento_encolar_log()

    ws_client = WebsocketClient(WSURL, redis_connection, logger)
    ws_client.start()


if __name__ == '__main__':
    start()
