# -*- coding: utf-8 -*-
from datetime import datetime, timedelta
from typing import Tuple
import logging
import random

from .celery import app
from .upsert import handle_upsert_hourse
from .parse import Parent, Result
from .webdriver import Webdriver
from .settings import Settings


@app.task
def upsert_rds(body: dict) -> str:
    try:
        return handle_upsert_hourse(data=body)
    except Exception as e:
        logging.error(e)
        return e


@app.task
def upsert_hourse(class_index: int, city_index: int, page: int):

    def create_param(result: Result) -> Tuple[int]:
        if result.has_next:
            return (class_index, city_index, page + 1)

        if city_index + 1 < len(Settings.cities.value):
            return (class_index, city_index + 1, 1)

        if class_index + 1 < len(Settings.class_mapping.value):
            return (class_index + 1, 0, 1)

        return (0, 0, 1)

    city = Settings.cities.value[city_index]
    struct = Settings.class_mapping.value[class_index]

    obj: Parent = struct(city=city, page=page)
    delay_second = random.uniform(Settings.min_delay_second.value, Settings.max_delay_second.value)
    delay = timedelta(seconds=delay_second)
    now = datetime.utcnow()
    try:
        result = obj.exec(driver=Webdriver)
        for body in result.body:
            upsert_rds.apply_async(args=(body,), eta=now)

        params = create_param(result=result)
        upsert_hourse.apply_async(args=params, eta=now + delay)

    except Exception as e:
        logging.error(e)

    return
