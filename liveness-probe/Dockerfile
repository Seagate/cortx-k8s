FROM node:14-alpine

WORKDIR /app

COPY ["app.js", "postStart.sh", "preStop.sh", "./"]
RUN ls

CMD ["node", "app.js"]
