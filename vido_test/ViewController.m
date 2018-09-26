//
//  ViewController.m
//  vido_test
//
//  Created by sking on 25/9/18.
//  Copyright © 2018年 sking. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#include "threadpool.h"
#include <netinet/in.h>
#include <sys/socket.h>
#include <arpa/inet.h>


@interface ViewController ()  <AVCaptureVideoDataOutputSampleBufferDelegate>
@property(nonatomic, strong) AVCaptureSession *captureSession;
@property (weak, nonatomic) IBOutlet UIImageView *img_view;
@property (weak, nonatomic) IBOutlet UIButton *btn;

@end

int count = 0;
BOOL btn_clik = false;
threadpool_t pool;
int conect_fd = 0;
struct _data
{
    size_t len;
    uint8_t *data;
};

void* mytask(void *arg)
{
    struct _data * data = (struct _data*)arg;
    NSLog(@"len:%ld",data->len);
    send(conect_fd, data->data,data->len,0);
    free(data->data);
    data->data = NULL;
    free(data);
    data = NULL;
    
    return NULL;
}

void connect_server()
{
    const char *host = "172.20.10.5";
    int  port= 8002;
    struct sockaddr_in server_addr;
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(port);
    server_addr.sin_addr.s_addr = inet_addr(host);
    bzero(&(server_addr.sin_zero),8);
    conect_fd = socket(AF_INET, SOCK_STREAM, 0);
    if(conect_fd<0)
    {
        perror("socket error");
        return ;
    }
    if(connect(conect_fd,(struct sockaddr *)&server_addr, sizeof(struct sockaddr_in)) == -1)
    {
        perror("connect error");
    }
    return;
}


@implementation ViewController



- (void)viewDidLoad {
    [super viewDidLoad];
    [self setcupSession];
    [self setupInput];
    [self setupOutput];
    connect_server();
    // Do any additional setup after loading the view, typically from a nib.
}

//#FF00FF
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)start{
    
    threadpool_init(&pool, 1);
    [_captureSession startRunning];
}

-(void)stop{
    threadpool_destroy(&pool);
     [_captureSession stopRunning];
}

- (IBAction)btn_click:(id)sender {
    NSLog(@"starting....");
    if(btn_clik == false)
    {
        [self start];
        [self.btn setBackgroundColor:[UIColor greenColor]];
        [self.btn setTitle:@"停止" forState:UIControlStateNormal];
        btn_clik = true;
    }else{
        [self stop];
        btn_clik = false;
        [self.btn setBackgroundColor:[UIColor grayColor]];
        [self.btn setTitle:@"开始" forState:UIControlStateNormal];
    }
}

// 设置捕获会话： 可以设置分辨率
-(void)setcupSession{
    AVCaptureSession *captureSession = [[AVCaptureSession alloc] init];
    _captureSession = captureSession;
    captureSession.sessionPreset = AVCaptureSessionPreset352x288;
    
}

//会话添加输入对象
- (void)setupInput {
    AVCaptureDevice *videoDevice = [self deviceWithPosition:AVCaptureDevicePositionFront];
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
    if([_captureSession canAddInput:videoInput]) {
        [_captureSession addInput:videoInput];
    }
}
//会话添加输出对象
- (void)setupOutput {
    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoOutput.minFrameDuration = CMTimeMake(1,25);
    videoOutput.videoSettings = @{(NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)};
    dispatch_queue_t queue = dispatch_queue_create("queue", DISPATCH_QUEUE_SERIAL);
    [videoOutput setSampleBufferDelegate:self queue:queue];
    if([_captureSession canAddOutput:videoOutput]) {
        [_captureSession addOutput:videoOutput];
    }
    AVCaptureConnection *connection = [videoOutput connectionWithMediaType:AVMediaTypeVideo];
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    connection.videoMirrored = YES;
}


- (AVCaptureDevice *)deviceWithPosition:(AVCaptureDevicePosition)position {
    NSArray *devices = [AVCaptureDevice devices];
    for (AVCaptureDevice *device in devices) {
        if(device.position == AVCaptureDevicePositionFront) {
            return device;
        }
    }
    return nil;
}


#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CIImage *ciImage = [CIImage imageWithCVImageBuffer:imageBuffer];
    UIImage *image = [UIImage imageWithCIImage:ciImage];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.img_view.image = image;
    });
    count++;
    if(count>50)
    {
        return;
    }
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    size_t pixelWidth = CVPixelBufferGetWidth(imageBuffer);
    size_t pixelHeight = CVPixelBufferGetHeight(imageBuffer);
    size_t y_size = pixelWidth * pixelHeight;
    size_t uv_size = y_size / 2;
    unsigned char *yuv_frame = (uint8_t*)malloc(uv_size + y_size);
    void *imageAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer,0); //yyyyy
    size_t row0=CVPixelBufferGetBytesPerRowOfPlane(imageBuffer,0);
    void *imageAddress1=CVPixelBufferGetBaseAddressOfPlane(imageBuffer,1);//UVUVUVUV
    size_t row1=CVPixelBufferGetBytesPerRowOfPlane(imageBuffer,1);
    for (int i=0; i<pixelHeight; ++i) {
        memcpy(yuv_frame+i*pixelWidth, imageAddress+i*row0, pixelWidth);
    }
    uint8_t *UV=imageAddress1;
    uint8_t *U=yuv_frame+y_size;
    uint8_t *V=U+y_size/4;
    for (int i=0; i<0.5*pixelHeight; i++)
    {
        for (int j=0; j<0.5*pixelWidth; j++)
        {
            *(U++)=UV[j<<1];
            *(V++)=UV[(j<<1)+1];
        }
       UV+=row1;
    }


//    unsigned char *y_frame = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
//    memcpy(yuv_frame, y_frame, y_size);
//    unsigned char *uv_frame = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1);
//    memcpy(yuv_frame + y_size, uv_frame, uv_size);
    
    
    struct _data *p_data = (struct _data*)malloc(sizeof(struct _data));
    p_data->data = yuv_frame;
    p_data->len = uv_size + y_size;
    threadpool_add_task(&pool, mytask, (void*)p_data);
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
}

@end










