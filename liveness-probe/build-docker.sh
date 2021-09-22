#! /bin/sh

docker build -t lp-test .

docker tag lp-test 10.235.177.135:5000/lp-test:2

docker push 10.235.177.135:5000/lp-test:2

echo "done"
